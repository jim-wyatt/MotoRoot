#!/usr/bin/env bash
# image/build/apply-local.sh - put this project's changes into the AOSP tree. Idempotent.
#
#   wsl -- bash image/build/apply-local.sh      (sync.sh and build-image.sh run it for you)
#
# Three kinds of input, all kept in this repository (or pinned by it) and never only in the tree:
#   image/product/   product definitions, copied to device/<name>/ in the tree (device/aospacademy/gsi
#                       defines the aospacademy_arm64 lunch target)
#   prebuilt APKs       listed in device/<name>/gsi/prebuilt/apks.txt as "<module apk> <pinned file>";
#                       the pinned files live in work/device-tools (downloaded and hash-checked by
#                       aosp-academy image inputs against toolchain.json) and are copied into the tree's
#                       prebuilt/ directory, never into the repository
#   image/patches/   unified diffs against one upstream project each, named
#                       <project-with-dashes>-NNNN-<what>.patch (frameworks-native-0001-....patch is
#                       applied inside frameworks/native). Applied with git apply; a patch the tree
#                       already carries is skipped, one that no longer applies stops the script so
#                       it can be rebased against the new tag rather than half-applied.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
TOOLS="$REPO_ROOT/work/device-tools"
AOSP_DIR="${AOSP_DIR:-$(python3 -c 'import json,os,sys; print(os.path.expanduser(json.load(open(sys.argv[1]))["deviceTools"]["aosp"].get("treeDir", "~/aosp")))' "$(dirname "${BASH_SOURCE[0]}")/../../toolchain.json")}"
cd "$AOSP_DIR" || { echo "no AOSP tree in $AOSP_DIR" >&2; exit 1; }
[ -d .repo ] || { echo "$AOSP_DIR is not a repo tree; run sync.sh first" >&2; exit 1; }

echo "== products"
for p in "$HERE"/../product/*/; do
  name="$(basename "$p")"
  mkdir -p "device/$name"
  # --delete keeps the tree copy identical to the repository copy, removed files included; the
  # APKs copied below are the one thing the tree has that the repository does not.
  rsync -a --delete --exclude '*.apk' --exclude '/gsi/adb_keys' "$p" "device/$name/" || { echo "   copying image/product/$name failed" >&2; exit 1; }
  echo "   device/$name <- image/product/$name"
done

echo "== prebuilt APKs"
for list in "$HERE"/../product/*/*/prebuilt/apks.txt; do
  [ -e "$list" ] || { echo "   (none)"; break; }
  dir="device/$(realpath --relative-to="$HERE/../product" "$(dirname "$list")")"
  while read -r module pinned; do
    case "$module" in ''|'#'*) continue;; esac
    src="$TOOLS/$pinned"
    [ -f "$src" ] || { echo "   $pinned missing from work/device-tools; run ./aosp-academy image inputs" >&2; exit 1; }
    if ! cmp -s "$src" "$dir/$module"; then cp "$src" "$dir/$module"; fi
    echo "   $dir/$module <- $pinned"
  done < "$list"
done

echo "== trusted adb keys"
# work/adb_keys (git-ignored, never in the repository): the public keys of this project's own PCs,
# one "<base64> user@host" line each, from %USERPROFILE%\.android\adbkey.pub. aospacademy_arm64.mk
# builds them in through PRODUCT_ADB_KEYS (/product/etc/security/adb_keys), so those PCs need no
# "Allow USB debugging?" tap after a fresh DSU install. Without the file the image trusts no PC.
keys_src="$REPO_ROOT/work/adb_keys"; keys_dst="device/aospacademy/gsi/adb_keys"
if [ -f "$keys_src" ]; then
  tr -d '\r' < "$keys_src" | grep -v '^[[:space:]]*$' > "$keys_dst.new"
  if grep -qv '^QAAAA[A-Za-z0-9+/=]* [^ ]*$' "$keys_dst.new" || [ ! -s "$keys_dst.new" ]; then
    rm -f "$keys_dst.new"; echo "   work/adb_keys: every line must be one adbkey.pub line (QAAAA... user@host)" >&2; exit 1
  fi
  if cmp -s "$keys_dst.new" "$keys_dst"; then rm -f "$keys_dst.new"; else mv -f "$keys_dst.new" "$keys_dst"; fi
  echo "   $keys_dst <- work/adb_keys ($(wc -l < "$keys_dst") keys: $(awk '{print $2}' "$keys_dst" | paste -sd' '))"
else
  rm -f "$keys_dst"; echo "   (no work/adb_keys: no PC is trusted in advance)"
fi

echo "== patches"
for patch in "$HERE"/../patches/*.patch; do
  [ -e "$patch" ] || { echo "   (none)"; break; }
  file="$(basename "$patch")"
  # project path: everything before -NNNN-, with dashes turned back into slashes
  project="$(echo "$file" | sed -E 's/-[0-9]{4}-.*//; s#-#/#g')"
  [ -d "$project/.git" ] || [ -f "$project/.git" ] || { echo "   $file: no project at $project" >&2; exit 1; }
  if git -C "$project" apply --reverse --check "$patch" 2>/dev/null; then
    echo "   $file: already applied"
  elif git -C "$project" apply --check "$patch" 2>/dev/null; then
    git -C "$project" apply "$patch" || { echo "   $file: git apply failed in $project" >&2; exit 1; }
    echo "   $file: applied"
  else
    echo "   $file: does not apply to $project; rebase it against this tag" >&2; exit 1
  fi
done
echo "== local changes in place"
