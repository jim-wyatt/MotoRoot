#!/usr/bin/env bash
# dev/aosp/setup.sh - prepare this WSL Ubuntu instance to build AOSP.
#
# Run inside WSL (from the dev shell: wsl -d Ubuntu -- bash dev/aosp/setup.sh). Idempotent.
# Installs the build dependencies Google lists for AOSP, the `repo` tool, and ccache, and
# creates the AOSP tree's parent directory on the WSL disk. Nothing here touches the repo on
# the Windows side except reading this script.
#
# Why WSL's own disk: an AOSP tree is 300-400 GB with its build output, must be on a
# case-sensitive filesystem, and building across the /mnt/c boundary is unsupported and slow.
set -euo pipefail

AOSP_DIR="${AOSP_DIR:-$HOME/aosp}"
CCACHE_DIR_DEFAULT="$HOME/.ccache-aosp"

echo "== apt packages"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  git-core gnupg flex bison build-essential zip curl zlib1g-dev libc6-dev-i386 \
  x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip \
  fontconfig python3 python3-pip rsync ccache repo git-lfs openjdk-21-jdk-headless \
  >/dev/null
git lfs install --skip-repo >/dev/null   # prebuilts use Git LFS; without it their checkout fails
echo "   repo:   $(repo --version 2>/dev/null | head -1 || echo installed)"
echo "   git-lfs: $(git lfs version 2>/dev/null || echo MISSING)"
echo "   ccache: $(ccache --version | head -1)"
echo "   java:   $(java -version 2>&1 | head -1)"

echo "== ccache (50 GB, speeds up rebuilds a lot)"
mkdir -p "$CCACHE_DIR_DEFAULT"
ccache -o cache_dir="$CCACHE_DIR_DEFAULT" >/dev/null
ccache -M 50G >/dev/null
if ! grep -q 'USE_CCACHE=1' "$HOME/.profile" 2>/dev/null; then
  cat >> "$HOME/.profile" <<'PROFILE'

# AOSP builds (OtomDev dev/aosp/setup.sh)
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
export CCACHE_DIR="$HOME/.ccache-aosp"
PROFILE
fi

echo "== git identity (repo refuses to sync without one)"
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "OtomDev builder"
git config --global user.email >/dev/null 2>&1 || git config --global user.email "builder@otomdev.invalid"
git config --global color.ui auto

mkdir -p "$AOSP_DIR"
echo "== ready. AOSP tree: $AOSP_DIR   disk: $(df -h "$AOSP_DIR" | awk 'NR==2 {print $4" free"}')"
