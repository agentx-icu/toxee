#!/bin/bash
#
# build_ios_sim_ffi.sh — cross-compile libtim2tox_ffi for the iOS Simulator.
#
# Day-to-day toxee development is on macOS; build.sh / build_ffi.sh only ever
# produced a *host* (macOS) libtim2tox_ffi.dylib, which physically cannot load
# on an iOS simulator (wrong Mach-O platform). run_toxee_ios.sh expects an iOS
# FFI artifact to be hand-provided but nothing built one — so the iOS app could
# never reach a working FFI backend. This script is that missing piece.
#
# It mirrors the cross settings from
# third_party/tim2tox/third_party/c-toxcore/other/deploy/ios.sh, but:
#   * builds the *tim2tox FFI shim* (not just toxcore),
#   * builds libsodium + libopus + libvpx from source for each target arch
#     (via tool/ci/build_av_deps.sh) with ToxAV ON so calling works on the
#     simulator (TOXAV=0 opts back into the stub variant),
#   * builds a UNIVERSAL (arm64 + x86_64) simulator binary by default. This is
#     required because several plugin pods (mobile_scanner / GoogleMLKit /
#     better_player_plus) ship no arm64-simulator slice, which forces the whole
#     Runner app to build x86_64 (Rosetta) on Apple Silicon. A fat FFI loads
#     under both a native arm64 sim and an x86_64/Rosetta sim.
#   * emits both a .framework (run_toxee_ios.sh's primary candidate) and a raw
#     .dylib, ad-hoc signed for the simulator loader.
#
# Output:
#   third_party/tim2tox/build/ios-sim/libtim2tox_ffi.dylib   (universal)
#   third_party/tim2tox/build/ios/tim2tox_ffi.framework      (picked up automatically)
#
# Env overrides: ARCHS (default "arm64 x86_64"), SDK (iphonesimulator|iphoneos),
#                IOS_MIN (default 13.0), SODIUM_VERSION (default 1.0.20),
#                TOXAV (default 1; TOXAV=0 builds the calling-stub variant).
set -euo pipefail

ARCHS="${ARCHS:-arm64 x86_64}"
SDK="${SDK:-iphonesimulator}"
IOS_MIN="${IOS_MIN:-13.0}"
SODIUM_VERSION="${SODIUM_VERSION:-1.0.20}"
TOXAV="${TOXAV:-1}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
# All logging goes to stderr so function stdout (captured via $(...)) stays clean.
info() { echo -e "${GREEN}[ios-ffi]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[ios-ffi]${NC} $*" >&2; }
err()  { echo -e "${RED}[ios-ffi]${NC} $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TIM2TOX_DIR="$REPO_ROOT/third_party/tim2tox"

[[ "$OSTYPE" == darwin* ]] || { err "macOS only"; exit 1; }
command -v cmake >/dev/null || { err "cmake missing"; exit 1; }
[[ -f "$TIM2TOX_DIR/ffi/CMakeLists.txt" ]] || { err "tim2tox submodule not populated: $TIM2TOX_DIR"; exit 1; }

NCPU="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
CLANG="$(xcrun -f clang)"
export FLUTTER_ROOT="${FLUTTER_ROOT:-$(cd "$(dirname "$(command -v flutter)")/.." && pwd)}"

triple_for() {
  local arch="$1"
  if [[ "$SDK" == "iphonesimulator" ]]; then echo "${arch}-apple-ios${IOS_MIN}-simulator";
  else echo "${arch}-apple-ios${IOS_MIN}"; fi
}
host_for() {
  case "$1" in
    arm64)  echo "aarch64-apple-darwin" ;;
    x86_64) echo "x86_64-apple-darwin" ;;
    *)      echo "${1}-apple-darwin" ;;
  esac
}

# Build libsodium (static) + the FFI shim for one arch; echoes the dylib path.
build_arch() {
  local arch="$1"
  local triple; triple="$(triple_for "$arch")"
  local tflags="-target $triple -isysroot $SYSROOT"
  local base="$TIM2TOX_DIR/build/ios-sim-${arch}"
  local dep_prefix="$base/deps-prefix"
  local ffi_build="$base/ffi-build"
  local src="$base/src"
  mkdir -p "$base" "$src"

  # --- libsodium ---
  if [[ -f "$dep_prefix/lib/libsodium.a" ]]; then
    info "[$arch] libsodium cached"
  else
    info "[$arch] building libsodium $SODIUM_VERSION ..."
    ( cd "$src"
      local tarball="libsodium-${SODIUM_VERSION}.tar.gz"
      local urls=(
        "https://github.com/jedisct1/libsodium/releases/download/${SODIUM_VERSION}-RELEASE/libsodium-${SODIUM_VERSION}.tar.gz"
        "https://download.libsodium.org/libsodium/releases/libsodium-${SODIUM_VERSION}-stable.tar.gz"
      )
      if [[ ! -f "$tarball" ]]; then
        local ok=0
        for u in "${urls[@]}"; do
          if curl -fLsS --retry 3 --retry-delay 2 --connect-timeout 30 -o "$tarball" "$u"; then ok=1; break; fi
        done
        [[ "$ok" == 1 ]] || { err "[$arch] libsodium download failed"; exit 1; }
      fi
      rm -rf extract && mkdir extract && tar xzf "$tarball" -C extract
      local sdir; sdir="$(dirname "$(find "$src/extract" -name configure -maxdepth 2 | head -1)")"
      cd "$sdir"
      ./configure --host="$(host_for "$arch")" --prefix="$dep_prefix" \
        --enable-static --disable-shared \
        CC="$CLANG" CFLAGS="$tflags -O2" LDFLAGS="$tflags" >"$base/libsodium-configure.log" 2>&1
      make -j"$NCPU" >"$base/libsodium-make.log" 2>&1
      make install >>"$base/libsodium-make.log" 2>&1
    )
  fi

  # --- ToxAV media deps (opus + vpx, shared pinned-source builder) ---
  local toxav_on="ON"
  if [[ "$TOXAV" == "1" ]]; then
    bash "$SCRIPT_DIR/ci/build_av_deps.sh" \
      --platform ios --sdk "$SDK" --arch "$arch" --min-version "$IOS_MIN" \
      --prefix "$dep_prefix" \
      --downloads "$TIM2TOX_DIR/build/mobile-deps/downloads" || { err "[$arch] AV deps build failed"; exit 1; }
  else
    toxav_on="OFF"
    warn "[$arch] TOXAV=0 — building calling-stub variant"
  fi

  # --- tim2tox FFI ---
  info "[$arch] configuring + building tim2tox_ffi (TOXAV=$toxav_on) ..."
  PKG_CONFIG_PATH="$dep_prefix/lib/pkgconfig" PKG_CONFIG_LIBDIR="$dep_prefix/lib/pkgconfig" \
  cmake -S "$TIM2TOX_DIR" -B "$ffi_build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_SYSROOT="$SYSROOT" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_C_FLAGS="-target $triple" \
    -DCMAKE_CXX_FLAGS="-target $triple" \
    -DCMAKE_EXE_LINKER_FLAGS="-target $triple" \
    -DCMAKE_SHARED_LINKER_FLAGS="-target $triple" \
    -DSTRICT_ABI=OFF -DBOOTSTRAP_DAEMON=OFF -DBUILD_TOXAV="$toxav_on" -DMUST_BUILD_TOXAV="$toxav_on" \
    -DDHT_BOOTSTRAP=OFF -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
    -DUNITTEST=OFF -DAUTOTEST=OFF -DBUILD_MISC_TESTS=OFF -DBUILD_FUN_UTILS=OFF \
    -DBUILD_FUZZ_TESTS=OFF -DUSE_IPV6=ON -DEXPERIMENTAL_API=OFF -DBUILD_FFI=ON \
    -DTIM2TOX_DEP_PREFIX="$dep_prefix" -DCMAKE_PREFIX_PATH="$dep_prefix" \
    -DCMAKE_FIND_ROOT_PATH="$dep_prefix" \
    >"$base/cmake-configure.log" 2>&1 || { err "[$arch] cmake configure failed"; tail -25 "$base/cmake-configure.log" >&2; exit 1; }
  cmake --build "$ffi_build" --target tim2tox_ffi -j"$NCPU" \
    >"$base/cmake-build.log" 2>&1 || { err "[$arch] cmake build failed"; tail -35 "$base/cmake-build.log" >&2; exit 1; }

  local dy; dy="$(find "$ffi_build" -name 'libtim2tox_ffi.dylib' -type f | head -1)"
  [[ -n "$dy" ]] || { err "[$arch] no libtim2tox_ffi.dylib produced"; exit 1; }
  echo "$dy"
}

info "ARCHS='$ARCHS'  sdk=$SYSROOT"
SLICES=()
for a in $ARCHS; do
  dy="$(build_arch "$a")"
  info "[$a] built: $dy"
  SLICES+=("$dy")
done
[[ ${#SLICES[@]} -gt 0 ]] || { err "no arch slices built (ARCHS='$ARCHS' empty?)"; exit 1; }

# ---------------------------------------------------------------------------
# lipo into a single universal dylib
# ---------------------------------------------------------------------------
OUT_BASE="$TIM2TOX_DIR/build/ios-sim"
mkdir -p "$OUT_BASE"
UNIVERSAL="$OUT_BASE/libtim2tox_ffi.dylib"
if [[ ${#SLICES[@]} -gt 1 ]]; then
  lipo -create "${SLICES[@]}" -output "$UNIVERSAL"
else
  cp "${SLICES[0]}" "$UNIVERSAL"
fi

# ---------------------------------------------------------------------------
# Verify Mach-O platform / arch / Dart symbol
# ---------------------------------------------------------------------------
echo -e "${CYAN}--- verification ---${NC}"
file "$UNIVERSAL"
lipo -info "$UNIVERSAL" || true
echo "build-version:"; vtool -show-build "$UNIVERSAL" 2>/dev/null | grep -iE "platform|minos" | head
# Captured symbol table (no `nm | grep -q` pipeline — grep -q's early exit
# SIGPIPEs nm and pipefail turns that into a false negative).
univ_syms="$(nm -g "$UNIVERSAL" 2>/dev/null || true)"
if [[ "$univ_syms" == *_Dart_PostCObject_DL* ]]; then
  info "Dart_PostCObject_DL symbol present"
else
  warn "Dart_PostCObject_DL symbol NOT found"
fi
# ToxAV must be REAL when requested — the marker symbol only exists under
# BUILD_TOXAV (stub builds silently no-op every call API otherwise).
if [[ "$TOXAV" == "1" ]]; then
  if [[ "$univ_syms" == *tim2tox_ffi_av_backend_toxav* ]]; then
    info "ToxAV backend confirmed (marker symbol present)"
  else
    err "ToxAV requested but marker symbol missing — calling would be a stub"; exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Package: framework (primary) + raw dylib, ad-hoc signed
# ---------------------------------------------------------------------------
OUT_FW="$TIM2TOX_DIR/build/ios/tim2tox_ffi.framework"
mkdir -p "$TIM2TOX_DIR/build/ios"
rm -rf "$OUT_FW"; mkdir -p "$OUT_FW"
cp "$UNIVERSAL" "$OUT_FW/tim2tox_ffi"
install_name_tool -id "@rpath/tim2tox_ffi.framework/tim2tox_ffi" "$OUT_FW/tim2tox_ffi"
cat > "$OUT_FW/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>tim2tox_ffi</string>
  <key>CFBundleIdentifier</key><string>com.toxee.tim2toxffi</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>tim2tox_ffi</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>${IOS_MIN}</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
</dict>
</plist>
PLIST
# These artifacts are dlopen'd from the app bundle, so a bad signature is a hard
# failure (the simulator loader rejects it) — abort instead of warning + DONE.
codesign --force --sign - "$OUT_FW" || { err "codesign framework failed"; exit 1; }
codesign --verify --strict "$OUT_FW" || { err "codesign --verify failed for framework"; exit 1; }

install_name_tool -id "@rpath/libtim2tox_ffi.dylib" "$UNIVERSAL"
codesign --force --sign - "$UNIVERSAL" || { err "codesign dylib failed"; exit 1; }
codesign --verify --strict "$UNIVERSAL" || { err "codesign --verify failed for dylib"; exit 1; }

info "Framework: $OUT_FW"
info "Dylib:     $UNIVERSAL"
echo -e "${GREEN}[ios-ffi] DONE${NC}"
