#!/usr/bin/env bash
# dev/aosp/build-after-sync.sh - run the GSI build as soon as the sync is done (overnight runs).
#
#   wsl -d Ubuntu -- bash dev/aosp/build-after-sync.sh      (run it in the background)
#
# Expects sync.sh to be running (or to have run) with its output in work/aosp-sync.log, ending in
# a "sync exit: N" line. If no sync is running and none has finished, it runs sync.sh itself.
# A running sync shows up as python3 .../.repo/repo/main.py ... sync, not as "repo sync".
# A sync that ended with errors is re-run once (repo sync is resumable: it only redoes what
# failed). Then build-gsi.sh runs. Everything is appended to work/aosp-build.log.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
L="$REPO_ROOT/work/aosp-sync.log"
B="$REPO_ROOT/work/aosp-build.log"

log() { echo "== $* ($(date '+%F %T'))" >> "$B"; }
log "build-after-sync started"

if ! grep -q '^sync exit:' "$L" 2>/dev/null && ! pgrep -f 'main.py.* sync' >/dev/null; then
  log "no sync running and none finished: running sync.sh"
  bash "$HERE/sync.sh" </dev/null >> "$L" 2>&1; echo "sync exit: $?" >> "$L"
fi
while ! grep -q '^sync exit:' "$L" 2>/dev/null; do sleep 60; done
log "sync finished: $(grep '^sync exit:' "$L" | tail -1)"

if ! grep -q '^sync exit: 0' "$L"; then
  log "sync ended with errors; re-running sync.sh once"
  if bash "$HERE/sync.sh" </dev/null >> "$B" 2>&1; then log "second sync OK"; else log "second sync failed; build not started"; exit 1; fi
fi

log "starting build"
bash "$HERE/build-gsi.sh" </dev/null >> "$B" 2>&1
rc=$?
log "build exit: $rc"
exit $rc
