#!/usr/bin/env bash
# image/build/check-patches.sh - do this project's patches still apply to the pinned AOSP tag?
#
#   bash image/build/check-patches.sh            (CI runs it on every change; no AOSP tree needed)
#   AOSP_TAG=android-17.0.0_r2 bash image/build/check-patches.sh     (before moving the tag)
#
# For each image/patches/<project-with-dashes>-NNNN-<what>.patch it clones only that project from
# android.googlesource.com at deviceTools.aosp.tag (shallow and blobless, with no checkout), then
# runs git apply --cached --check against its index, which fetches only the files the patch
# touches. Seconds, against the hours a build takes to reach a patch that no longer applies, and
# the first thing to fail when the tag moves. The project path comes from the file name exactly as
# apply-local.sh reads it; its AOSP repository is platform/<path>, true of every project patched
# so far.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
TAG="${AOSP_TAG:-$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["deviceTools"]["aosp"]["tag"])' "$REPO_ROOT/toolchain.json")}"
REMOTE="${AOSP_REMOTE:-https://android.googlesource.com}"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

echo "== patches against $TAG"
fail=0
PATCH_DIR="${PATCH_DIR:-$HERE/../patches}"
for patch in "$PATCH_DIR"/*.patch; do
  [ -e "$patch" ] || { echo "   (none)"; break; }
  file="$(basename "$patch")"
  project="$(echo "$file" | sed -E 's/-[0-9]{4}-.*//; s#-#/#g')"
  dir="$SCRATCH/$project"
  if [ ! -d "$dir/.git" ]; then
    # core.protectNTFS off: some projects carry file names Windows can't hold (build/blueprint has
    # one with a '*'). Nothing is checked out, so they never reach the disk.
    if ! git -c core.protectNTFS=false clone -q --depth 1 --branch "$TAG" --filter=blob:none --no-checkout \
           "$REMOTE/platform/$project" "$dir" 2> >(grep -v 'is not a commit' >&2) \
       || ! git -C "$dir" -c core.protectNTFS=false read-tree HEAD; then
      echo "   $file: cannot clone platform/$project at $TAG" >&2; fail=1; continue
    fi
  fi
  if out="$(git -C "$dir" apply --cached --check "$patch" 2>&1)"; then
    echo "   $file: applies to $project"
  else
    echo "   $file: does NOT apply to $project at $TAG; rebase it" >&2
    echo "${out//$'\n'/$'\n'      }" | sed '1s/^/      /' >&2
    fail=1
  fi
done
exit "$fail"
