#!/usr/bin/env bash
# image/build/build-image.sh - build the GSI (aosp_arm64) from the synced tree and hand the image back.
#
# Run inside WSL after sync.sh:  wsl -- bash image/build/build-image.sh
# The lunch target comes from toolchain.json (deviceTools.aosp.lunch). The first build takes
# hours and all cores; later builds are incremental. On success the system image is copied to
# work/device-tools/gsi/own/ on the Windows side, where Install-Gsi.ps1 -Image can boot it
# through DSU exactly like Google's image.
# No `set -e`/`set -u`: AOSP's envsetup.sh and lunch are not written for strict mode (they read
# unset variables and return non-zero on the way to success). Failures are checked explicitly.
set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
AOSP_DIR="${AOSP_DIR:-$HOME/aosp}"
# Parallel jobs. All cores is right for the C++ phase, but the later R8/d8 phase runs one multi-GB JVM
# per job; on a 32-core box with WSL capped at 26 GB that filled 16 GB of swap and the kernel killed
# ninja at 76%. JOBS=12 keeps that phase inside memory; the build resumes where it stopped.
JOBS="${JOBS:-$(nproc)}"
LUNCH="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["deviceTools"]["aosp"]["lunch"])' "$REPO_ROOT/toolchain.json")"
# DEST_DIR, not OUT_DIR: OUT_DIR is AOSP's own build variable and envsetup.sh uses it.
DEST_DIR="$REPO_ROOT/work/device-tools/gsi/own"

cd "$AOSP_DIR" || exit 1
[ -f build/envsetup.sh ] || { echo "no AOSP tree in $AOSP_DIR; run sync.sh first" >&2; exit 1; }
# This project's product and patches, from the repository into the tree (idempotent).
bash "$HERE/apply-local.sh" || exit 1
# shellcheck disable=SC1091
source build/envsetup.sh
echo "== lunch $LUNCH"
lunch "$LUNCH" || { echo "lunch failed; run 'lunch' in $AOSP_DIR to list this tag's targets and fix deviceTools.aosp.lunch" >&2; exit 1; }
echo "== build started $(date)"
echo "== m -j$JOBS"
m -j"$JOBS" || { echo "build failed" >&2; exit 1; }
PRODUCT_OUT="$(get_build_var PRODUCT_OUT)"
[ -f "$PRODUCT_OUT/system.img" ] || { echo "no system.img in $PRODUCT_OUT" >&2; exit 1; }
echo "== build finished $(date)"
[ -f "$PRODUCT_OUT/system/build.prop" ] || { echo "no system/build.prop in $PRODUCT_OUT" >&2; exit 1; }
mkdir -p "$DEST_DIR"
# The previous build's files go first, so none of them (vbmeta.img when this build has none, say)
# stays beside the new image, where Install-Gsi.ps1 -Image would pack it into the DSU zip.
rm -f "$DEST_DIR"/system.img "$DEST_DIR"/vbmeta.img "$DEST_DIR"/build.prop "$DEST_DIR"/system.img.sha256
cp "$PRODUCT_OUT/system.img" "$DEST_DIR/system.img" || { echo "copying system.img failed" >&2; exit 1; }
cp "$PRODUCT_OUT/system/build.prop" "$DEST_DIR/build.prop" || { echo "copying build.prop failed" >&2; exit 1; }
if [ -f "$PRODUCT_OUT/vbmeta.img" ]; then
  cp "$PRODUCT_OUT/vbmeta.img" "$DEST_DIR/vbmeta.img" || { echo "copying vbmeta.img failed" >&2; exit 1; }
fi
# A checksum beside the image, so a copy on another machine can be verified (Get-RemoteImage.ps1).
(cd "$DEST_DIR" && sha256sum system.img > system.img.sha256)
# Optional second copy for another machine to pull, e.g. a chrooted SFTP folder on WSL's own disk
# (see "Building on one machine, installing from another" in docs/develop/aosp-build.md). Each file
# is written under a temporary name and renamed, and the checksum goes last, so a pull that
# overlaps a build never sees a half-written image paired with the new checksum.
# The image is also published in PARTS pieces (system.img.part00 ...), listed with their SHA-256
# in system.img.parts: the VPN path to the install PC limits each connection, not the total, so
# Get-RemoteImage.ps1 pulls the parts over parallel streams (8 streams: 1.8 GB in ~4.5 min instead
# of 13) and joins them. The full system.img stays for pullers that don't use parts.
PARTS="${PARTS:-16}"
if [ -n "${PUBLISH_DIR:-}" ]; then
  mkdir -p "$PUBLISH_DIR" || { echo "cannot create PUBLISH_DIR $PUBLISH_DIR" >&2; exit 1; }
  publish_failed() { echo "publishing $1 to $PUBLISH_DIR failed" >&2; exit 1; }
  # Checksum and parts list first (a puller then sees no image at all, not a mismatched one), and
  # every old file, so nothing of the previous build stays published beside this one.
  rm -f "$PUBLISH_DIR/system.img.sha256" "$PUBLISH_DIR/system.img.parts" "$PUBLISH_DIR"/system.img.part[0-9]* \
        "$PUBLISH_DIR"/.system.img.part[0-9]* "$PUBLISH_DIR/vbmeta.img" "$PUBLISH_DIR/build.prop"
  for f in system.img vbmeta.img build.prop; do
    [ -f "$DEST_DIR/$f" ] || continue    # only vbmeta.img can be missing here; its old copy is gone
    cp "$DEST_DIR/$f" "$PUBLISH_DIR/.$f.part" && chmod 644 "$PUBLISH_DIR/.$f.part" && mv -f "$PUBLISH_DIR/.$f.part" "$PUBLISH_DIR/$f" \
      || publish_failed "$f"
  done
  ( cd "$PUBLISH_DIR" && split -n "$PARTS" -d -a 2 system.img .system.img.part \
      && for p in .system.img.part[0-9]*; do chmod 644 "$p" && mv -f "$p" "${p#.}" || exit 1; done \
      && sha256sum system.img.part[0-9]* > .system.img.parts && chmod 644 .system.img.parts \
      && mv -f .system.img.parts system.img.parts ) || publish_failed "the image parts"
  cp "$DEST_DIR/system.img.sha256" "$PUBLISH_DIR/.system.img.sha256.part" && chmod 644 "$PUBLISH_DIR/.system.img.sha256.part" \
    && mv -f "$PUBLISH_DIR/.system.img.sha256.part" "$PUBLISH_DIR/system.img.sha256" || publish_failed system.img.sha256
  echo "== published to $PUBLISH_DIR ($PARTS parts)"
fi
echo "== image: $DEST_DIR/system.img ($(du -h "$DEST_DIR/system.img" | cut -f1))"
echo "   fingerprint: $(grep '^ro.system.build.fingerprint=' "$DEST_DIR/build.prop" 2>/dev/null | cut -d= -f2)"
