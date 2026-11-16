#!/usr/bin/env bash
# dev/aosp/build-gsi.sh - build the GSI (aosp_arm64) from the synced tree and hand the image back.
#
# Run inside WSL after sync.sh:  wsl -d Ubuntu -- bash dev/aosp/build-gsi.sh
# The lunch target comes from dev/toolchain.json (deviceTools.aosp.lunch). The first build takes
# hours and all cores; later builds are incremental. On success the system image is copied to
# work/device-tools/gsi/own/ on the Windows side, where Install-Gsi.ps1 -Image can boot it
# through DSU exactly like Google's image.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
AOSP_DIR="${AOSP_DIR:-$HOME/aosp}"
LUNCH="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["deviceTools"]["aosp"]["lunch"])' "$HERE/../toolchain.json")"
OUT_DIR="$REPO_ROOT/work/device-tools/gsi/own"

cd "$AOSP_DIR"
[ -f build/envsetup.sh ] || { echo "no AOSP tree in $AOSP_DIR; run sync.sh first" >&2; exit 1; }
# shellcheck disable=SC1091
source build/envsetup.sh
export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR="$HOME/.ccache-aosp"
echo "== lunch $LUNCH"
lunch "$LUNCH"
echo "== build started $(date)"
m -j"$(nproc)"
PRODUCT_OUT="$(get_build_var PRODUCT_OUT)"
echo "== build finished $(date)"
mkdir -p "$OUT_DIR"
cp "$PRODUCT_OUT/system.img" "$OUT_DIR/system.img"
[ -f "$PRODUCT_OUT/vbmeta.img" ] && cp "$PRODUCT_OUT/vbmeta.img" "$OUT_DIR/vbmeta.img"
cp "$PRODUCT_OUT/system/build.prop" "$OUT_DIR/build.prop" 2>/dev/null || true
echo "== image: $OUT_DIR/system.img ($(du -h "$OUT_DIR/system.img" | cut -f1))"
echo "   fingerprint: $(grep '^ro.system.build.fingerprint=' "$OUT_DIR/build.prop" 2>/dev/null | cut -d= -f2)"
