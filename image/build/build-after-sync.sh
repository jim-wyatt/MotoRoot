#!/usr/bin/env bash
# image/build/build-after-sync.sh - run the GSI build as soon as the sync is done (overnight runs).
#
#   wsl -- bash image/build/build-after-sync.sh      (run it in the background)
#
# Waits for a sync.sh that is already running with its output appended to work/aosp-sync.log and
# ending in a "sync exit: N" line; if none is running, it runs sync.sh itself (a sync of an
# up-to-date tree is quick). Results logged before it started are ignored.
# A running sync shows up as python3 .../.repo/repo/main.py ... sync, not as "repo sync".
# A sync that ended with errors is re-run once (repo sync is resumable: it only redoes what
# failed). Then build-image.sh runs. Everything is appended to work/aosp-build.log.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
L="$REPO_ROOT/work/aosp-sync.log"
B="$REPO_ROOT/work/aosp-build.log"

log() { echo "== $* ($(date '+%F %T'))" >> "$B"; }
log "build-after-sync started"

# The sync log is appended across runs, so only what is written after this point counts: an older
# run's "sync exit:" line must neither end the wait nor pass for this sync's result.
start="$(stat -c %s "$L" 2>/dev/null || echo 0)"
last_exit() { tail -c +"$((start + 1))" "$L" 2>/dev/null | grep '^sync exit:' | tail -1; }

if ! pgrep -f 'main.py.* sync' >/dev/null; then
  log "no sync running: running sync.sh"
  bash "$HERE/sync.sh" </dev/null >> "$L" 2>&1; echo "sync exit: $?" >> "$L"
fi
while [ -z "$(last_exit)" ]; do sleep 60; done
result="$(last_exit)"
log "sync finished: $result"

if [ "$result" != "sync exit: 0" ]; then
  log "sync ended with errors; re-running sync.sh once"
  if bash "$HERE/sync.sh" </dev/null >> "$B" 2>&1; then log "second sync OK"; else log "second sync failed; build not started"; exit 1; fi
fi

log "starting build"
bash "$HERE/build-image.sh" </dev/null >> "$B" 2>&1
rc=$?
log "build exit: $rc"
exit $rc
