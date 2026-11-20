#!/usr/bin/env bash
# image/build/setup.sh - prepare this Linux host (Ubuntu/Debian: native, WSL2, VM) to build AOSP.
#
# Run on the build node:  ./aosp-academy image setup   (or bash image/build/setup.sh). Idempotent.
# Installs the build dependencies Google lists for AOSP, the `repo` tool and git-lfs, and
# creates the AOSP tree's parent directory on this host's own disk. Nothing here touches the repo on
# the Windows side except reading this script.
#
# Why the host's own disk (on WSL2: the WSL disk, not /mnt/c): an AOSP tree is 300-400 GB with its build output, must be on a
# case-sensitive filesystem, and building across the /mnt/c boundary is unsupported and slow.
set -euo pipefail

AOSP_DIR="${AOSP_DIR:-$(python3 -c 'import json,os,sys; print(os.path.expanduser(json.load(open(sys.argv[1]))["deviceTools"]["aosp"].get("treeDir", "~/aosp")))' "$(dirname "${BASH_SOURCE[0]}")/../../toolchain.json")}"

echo "== apt packages"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  git-core gnupg flex bison build-essential zip curl zlib1g-dev libc6-dev-i386 \
  x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip \
  fontconfig python3 python3-pip rsync repo git-lfs openjdk-21-jdk-headless \
  >/dev/null
git lfs install --skip-repo >/dev/null   # prebuilts use Git LFS; without it their checkout fails
echo "   repo:   $(repo --version 2>/dev/null | head -1 || echo installed)"
echo "   git-lfs: $(git lfs version 2>/dev/null || echo MISSING)"
echo "   java:   $(java -version 2>&1 | head -1)"

# No ccache: AOSP's build sandbox mounts only out/ and /tmp writable, so ccache fails with
# "Read-only file system", and AOSP's own build/make/core/ccache.mk says it adds little over
# incremental builds. An earlier version of this script exported USE_CCACHE in ~/.profile;
# remove that so a hand-run `m` in a login shell does not hit the same failure.
if grep -q '^# AOSP builds (.*dev/aosp/setup.sh)$' "$HOME/.profile" 2>/dev/null; then
  sed -i '/^# AOSP builds (.*dev\/aosp\/setup.sh)$/,/^export CCACHE_DIR=/d' "$HOME/.profile"
  echo "== removed the old ccache exports from ~/.profile"
fi

echo "== git identity (repo refuses to sync without one)"
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "aosp-academy builder"
git config --global user.email >/dev/null 2>&1 || git config --global user.email "builder@aosp-academy.invalid"
git config --global color.ui auto

mkdir -p "$AOSP_DIR"
echo "== ready. AOSP tree: $AOSP_DIR   disk: $(df -h "$AOSP_DIR" | awk 'NR==2 {print $4" free"}')"
