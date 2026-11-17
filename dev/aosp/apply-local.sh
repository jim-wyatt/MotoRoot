#!/usr/bin/env bash
# dev/aosp/apply-local.sh - put this project's changes into the AOSP tree. Idempotent.
#
#   wsl -d Ubuntu -- bash dev/aosp/apply-local.sh      (sync.sh and build-gsi.sh run it for you)
#
# Two kinds of change, both kept in this repository and never only in the tree:
#   dev/aosp/product/   product definitions, copied to device/<name>/ in the tree (device/vedotom/gsi
#                       defines the vedotom_arm64 lunch target: aosp_arm64 plus our settings)
#   dev/aosp/patches/   unified diffs against one upstream project each, named
#                       <project-with-dashes>-NNNN-<what>.patch (frameworks-native-0001-....patch is
#                       applied inside frameworks/native). Applied with git apply; a patch the tree
#                       already carries is skipped, one that no longer applies stops the script so
#                       it can be rebased against the new tag rather than half-applied.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AOSP_DIR="${AOSP_DIR:-$HOME/aosp}"
cd "$AOSP_DIR" || { echo "no AOSP tree in $AOSP_DIR" >&2; exit 1; }
[ -d .repo ] || { echo "$AOSP_DIR is not a repo tree; run sync.sh first" >&2; exit 1; }

echo "== products"
for p in "$HERE"/product/*/; do
  name="$(basename "$p")"
  mkdir -p "device/$name"
  # --delete keeps the tree copy identical to the repository copy, removed files included.
  rsync -a --delete "$p" "device/$name/" && echo "   device/$name <- dev/aosp/product/$name"
done

echo "== patches"
for patch in "$HERE"/patches/*.patch; do
  [ -e "$patch" ] || { echo "   (none)"; break; }
  file="$(basename "$patch")"
  # project path: everything before -NNNN-, with dashes turned back into slashes
  project="$(echo "$file" | sed -E 's/-[0-9]{4}-.*//; s#-#/#g')"
  [ -d "$project/.git" ] || [ -f "$project/.git" ] || { echo "   $file: no project at $project" >&2; exit 1; }
  if git -C "$project" apply --reverse --check "$patch" 2>/dev/null; then
    echo "   $file: already applied"
  elif git -C "$project" apply --check "$patch" 2>/dev/null; then
    git -C "$project" apply "$patch" && echo "   $file: applied"
  else
    echo "   $file: does not apply to $project; rebase it against this tag" >&2; exit 1
  fi
done
echo "== local changes in place"
