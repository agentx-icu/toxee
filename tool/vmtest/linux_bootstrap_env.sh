#!/usr/bin/env bash
# One-time environment bootstrap for the Ubuntu VM test host (vmtest campaign).
# Installs the linux-desktop toolchain + Flutter (linux-arm64 host) if missing.
# Idempotent: safe to re-run. Run it as the normal login user (needs sudo for apt).
#
#   bash /media/psf/Home/chat-uikit/toxee-vmtest-linux/tool/vmtest/linux_bootstrap_env.sh
#
# Note: stable Flutter tarballs are x64-only, so on an arm64 host this installs
# from a git clone at the pinned tag (the flutter tool then downloads the
# arm64 Dart SDK + engine artifacts itself; `flutter precache --linux` proves it).
set -uo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.9}"
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/flutter}"

log() { echo "[linux-bootstrap] $*"; }

log "apt deps..."
sudo apt-get update -qq || log "WARN: apt update failed (continuing)"
# NEEDRESTART_MODE=a: Ubuntu desktop's needrestart post-install hook is
# INTERACTIVE by default and silently hangs a non-TTY apt run waiting for a
# service-restart choice (DEBIAN_FRONTEND only covers debconf, not needrestart).
sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 apt-get install -y -qq \
  curl ca-certificates xz-utils jq git unzip zip cmake ninja-build pkg-config \
  build-essential clang libgtk-3-dev libsecret-1-dev libsodium-dev libopus-dev \
  libvpx-dev libssl-dev libsqlite3-dev patchelf xvfb liblzma-dev mesa-utils \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good >/dev/null
log "apt done (rc=$?)"

if [ -x "$FLUTTER_HOME/bin/flutter" ]; then
  log "flutter already present at $FLUTTER_HOME"
else
  arch="$(uname -m)"
  archive=""
  if [ "$arch" = "x86_64" ]; then
    releases="$(curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json || true)"
    archive="$(printf '%s' "$releases" | jq -r --arg v "$FLUTTER_VERSION" \
      '[.releases[] | select(.version==$v and .channel=="stable")][0].archive // empty')"
  fi
  if [ -n "$archive" ]; then
    url="https://storage.googleapis.com/flutter_infra_release/releases/$archive"
    log "downloading $url"
    curl -fSL "$url" -o /tmp/flutter_sdk.tar.xz
    tar -xJf /tmp/flutter_sdk.tar.xz -C "$(dirname "$FLUTTER_HOME")"
  else
    log "no stable tarball for $arch; cloning flutter@$FLUTTER_VERSION (this downloads the $arch Dart SDK on first run)"
    git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME"
  fi
fi

export PATH="$FLUTTER_HOME/bin:$PATH"
flutter config --no-analytics >/dev/null 2>&1 || true
log "flutter --version (first run downloads the Dart SDK)..."
flutter --version 2>&1 | sed -n '1,4p'
log "flutter precache --linux (proves linux-$(uname -m) engine artifacts exist)..."
flutter precache --linux 2>&1 | tail -4
log "flutter doctor:"
flutter doctor 2>&1 | sed -n '1,14p'
log "DONE"
