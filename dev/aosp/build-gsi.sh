#!/usr/bin/env bash
# dev/aosp/build-gsi.sh - build the GSI (aosp_arm64) from the synced tree and hand the image back.
#
# Run inside WSL after sync.sh:  wsl -- bash dev/aosp/build-gsi.sh
# The lunch target comes from dev/toolchain.json (deviceTools.aosp.lunch). The first build takes
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
LUNCH="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["deviceTools"]["aosp"]["lunch"])' "$HERE/../toolchain.json")"
# DEST_DIR, not OUT_DIR: OUT_DIR is AOSP's own build variable and envsetup.sh uses it.
DEST_DIR="$REPO_ROOT/work/device-tools/gsi/own"

cd "$AOSP_DIR"
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
mkdir -p "$DEST_DIR"
cp "$PRODUCT_OUT/system.img" "$DEST_DIR/system.img"
[ -f "$PRODUCT_OUT/vbmeta.img" ] && cp "$PRODUCT_OUT/vbmeta.img" "$DEST_DIR/vbmeta.img"
cp "$PRODUCT_OUT/system/build.prop" "$DEST_DIR/build.prop" 2>/dev/null || true
# A checksum beside the image, so a copy on another machine can be verified (Get-RemoteImage.ps1).
(cd "$DEST_DIR" && sha256sum system.img > system.img.sha256)
echo "== image: $DEST_DIR/system.img ($(du -h "$DEST_DIR/system.img" | cut -f1))"
echo "   fingerprint: $(grep '^ro.system.build.fingerprint=' "$DEST_DIR/build.prop" 2>/dev/null | cut -d= -f2)"
