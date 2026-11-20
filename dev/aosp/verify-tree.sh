#!/usr/bin/env bash
# dev/aosp/verify-tree.sh - find and repair half-checked-out projects in the AOSP tree.
#
#   wsl -- bash dev/aosp/verify-tree.sh        (sync.sh runs it after every sync)
#
# A sync interrupted during checkout (Ctrl-C, a killed process, WSL shut down) can leave a project
# with the right HEAD but a half-written work tree. The next `repo sync` sees HEAD, leaves it alone
# and reports success, and the build then fails in confusing ways ("unrecognized module type"
# when prebuilts/clang's soong/ directory is missing, for example). Such a project shows every
# missing file as a staged deletion ("D " in `git status --porcelain`) and nothing else, which no
# hand edit produces, so those projects are reset to HEAD. Projects with any other change are
# yours (see "Changing something" on the docs page) and are only listed, never touched.
set -uo pipefail
AOSP_DIR="${AOSP_DIR:-$(python3 -c 'import json,os,sys; print(os.path.expanduser(json.load(open(sys.argv[1]))["deviceTools"]["aosp"].get("treeDir", "~/aosp")))' "$(dirname "${BASH_SOURCE[0]}")/../toolchain.json")}"
JOBS="${JOBS:-$(nproc)}"
cd "$AOSP_DIR" || { echo "no AOSP tree in $AOSP_DIR" >&2; exit 1; }
[ -d .repo ] || { echo "$AOSP_DIR is not a repo tree; run sync.sh first" >&2; exit 1; }

echo "== verifying $(repo list -p | wc -l) work trees ($(date '+%T'))"
dirty="$(repo forall -j"$JOBS" -c 'git status --porcelain --untracked-files=no 2>/dev/null | grep -q . && echo "$REPO_PATH"' 2>/dev/null | sort)"
incomplete=0 edited=0 failed=0
for p in $dirty; do
  if git -C "$p" status --porcelain --untracked-files=no | grep -qv '^D '; then
    echo "   local changes (left alone): $p"; edited=$((edited+1))
  else
    n=$(git -C "$p" status --porcelain --untracked-files=no | wc -l)
    echo "   incomplete checkout ($n files missing), resetting to HEAD: $p"
    if git -C "$p" reset -q --hard HEAD && [ -z "$(git -C "$p" status --porcelain --untracked-files=no)" ]; then
      incomplete=$((incomplete+1))
    else
      echo "   reset FAILED: $p" >&2; failed=$((failed+1))
    fi
  fi
done
echo "== verified ($(date '+%T')): $incomplete repaired, $edited with local changes, $failed still broken"
[ "$failed" -eq 0 ]
