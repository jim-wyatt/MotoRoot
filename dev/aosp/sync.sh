#!/usr/bin/env bash
# dev/aosp/sync.sh - check out the pinned AOSP release into $AOSP_DIR (default ~/aosp).
#
# Run inside WSL after setup.sh:  wsl -d Ubuntu -- bash dev/aosp/sync.sh
# The tag comes from dev/toolchain.json (deviceTools.aosp.tag) so the source matches the GSI
# build that was validated on the device. A partial clone keeps the first download to roughly
# 60-100 GB; `repo sync` is resumable, so re-run this if it is interrupted.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AOSP_DIR="${AOSP_DIR:-$HOME/aosp}"
TAG="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["deviceTools"]["aosp"]["tag"])' "$HERE/../toolchain.json")"
MANIFEST="https://android.googlesource.com/platform/manifest"
JOBS="${JOBS:-$(( $(nproc) / 2 ))}"

# Several prebuilts projects (bundletool, jdk8, bazel, tools) keep their files in Git LFS; without
# git-lfs their checkout fails with "Cannot initialize work tree". setup.sh installs it.
command -v git-lfs >/dev/null || { echo "git-lfs is not installed; run dev/aosp/setup.sh first" >&2; exit 1; }

mkdir -p "$AOSP_DIR"; cd "$AOSP_DIR"
if [ ! -d .repo ]; then
  echo "== repo init $TAG"
  repo init -u "$MANIFEST" -b "$TAG" --partial-clone --clone-filter=blob:limit=10M --depth=1 --no-repo-verify
else
  echo "== repo already initialised: $(cat .repo/manifests/.git/HEAD 2>/dev/null || true)"
fi
echo "== repo sync ($JOBS jobs) started $(date)"
repo sync -c -j"$JOBS" --no-tags --no-clone-bundle --optimized-fetch --prune
echo "== sync complete $(date)   size: $(du -sh "$AOSP_DIR" | cut -f1)"
# A sync that was interrupted during checkout leaves projects repo no longer looks at; see verify-tree.sh.
bash "$HERE/verify-tree.sh"
# Re-apply this project's product and patches after the tree moved.
bash "$HERE/apply-local.sh"
