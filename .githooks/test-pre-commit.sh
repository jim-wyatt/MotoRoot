#!/usr/bin/env bash
# Tests .githooks/pre-commit in a throwaway repository: every forbidden kind of file, force-added
# past .gitignore, must be blocked, and ordinary files must pass.
#   bash .githooks/test-pre-commit.sh        (CI runs it: .github/workflows/checks.yml)
set -uo pipefail
hook="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pre-commit"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
git init -q "$tmp" && cd "$tmp" || exit 1
git config user.email t@example.invalid; git config user.name test; git config core.autocrlf false
fail=0

expect() {   # expect <blocked|allowed> <path> [content]
  local want="$1" path="$2" content="${3:-x}"
  git rm -rq --cached . >/dev/null 2>&1
  mkdir -p "$(dirname "$path")"; printf '%s\n' "$content" > "$path"
  git add -f -- "$path"
  if bash "$hook" >/dev/null 2>&1; then got=allowed; else got=blocked; fi
  if [ "$got" != "$want" ]; then echo "FAIL: $path was $got, expected $want"; fail=1; fi
  rm -f -- "$path"
}

for p in work/notes.txt private-backups/lk_a.img x/private-backups/a lk-analysis/a.txt \
         dev/.tools/r8.jar dev/build/x site/index.html .venv/lib/x.py dev/.venv-docs/x \
         traces/a.pftrace app/traces/b.txt blobs/vendor.so extracted/x captures/a.png screenshots/s.png \
         system.img dump.BIN app.apk driver.msi run.log key.pem release.jks keystore.properties \
         local.properties .env .env.local unlock-keys.txt \
         adbkey home/.android/adbkey adb_keys work2/adb_keys wifi.json \
         a.pftrace b.perfetto-trace screen.mp4 rec.mkv libfoo.so; do
  expect blocked "$p"
done
# Made-up identifiers, assembled at run time so this file never holds an identifier-shaped line
# (the hook would rightly block it). Never paste a real device's serial or IMEI here.
fake_imei="$(printf '%s%s' 1234567 89012345)"
fake_serial="$(printf '%s%s' TESTSER 0000)"
expect blocked notes.txt "IMEI: $fake_imei"
expect blocked notes.txt "ro.serialno=$fake_serial"

for p in README.md dev/Test-DevEnv.ps1 device/modules/manifests/x.json docs/a.md adbkey.pub.md \
         device/helpers/UpdateHelper.java dev/aosp/build-gsi.sh; do
  expect allowed "$p"
done
expect allowed notes.txt "sha256 2c8de56238978b9b8a681f7cc84c113e84b7c8ff78ea0b6c55fa13646a777dc5"

if [ "$fail" -eq 0 ]; then echo "pre-commit hook: all cases behave"; fi
exit "$fail"
