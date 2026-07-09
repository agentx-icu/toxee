#!/bin/bash
#
# build_android_ffi.sh — cross-compile libtim2tox_ffi.so for Android via the NDK.
#
# Like the iOS case, build.sh / build_ffi.sh only ever produced a host (macOS)
# libtim2tox_ffi.dylib; nothing built the Android .so, yet run_toxee_android.sh
# and the Android FFI loader (DynamicLibrary.open('libtim2tox_ffi.so')) expect
# one per-ABI under jniLibs/. This is that missing piece.
#
# For each ABI it builds libsodium + libopus + libvpx (static, NDK clang) +
# cross-builds toxcore + the FFI shim with ToxAV ON (calling works), then
# drops the resulting libtim2tox_ffi.so into
# android/app/src/main/jniLibs/<abi>/ so the Flutter Gradle build packages it
# into the APK.
#
# Env overrides: ABIS (default "arm64-v8a"; e.g. "arm64-v8a x86_64 armeabi-v7a"),
#                ANDROID_API (default 21), NDK (auto-detected),
#                SODIUM_VERSION (default 1.0.20),
#                TOXAV (default 1; TOXAV=0 builds the calling-stub variant).
set -euo pipefail

ABIS="${ABIS:-arm64-v8a}"
ANDROID_API="${ANDROID_API:-21}"
SODIUM_VERSION="${SODIUM_VERSION:-1.0.20}"
TOXAV="${TOXAV:-1}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
# All logging to stderr so function stdout (captured via $(...)) stays clean.
info() { echo -e "${GREEN}[android-ffi]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[android-ffi]${NC} $*" >&2; }
err()  { echo -e "${RED}[android-ffi]${NC} $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TIM2TOX_DIR="$REPO_ROOT/third_party/tim2tox"
JNI_LIBS="$REPO_ROOT/android/app/src/main/jniLibs"

command -v cmake >/dev/null || { err "cmake missing"; exit 1; }
[[ -f "$TIM2TOX_DIR/ffi/CMakeLists.txt" ]] || { err "tim2tox submodule not populated"; exit 1; }

# --- locate NDK ---
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
if [[ -z "${NDK:-}" ]]; then
  # Pick the HIGHEST-version NDK that is actually COMPLETE (has the cmake
  # toolchain). A stalled/partial download (e.g. 28.2 missing build/cmake) is
  # otherwise selected by a plain `tail -1` and fails the build.
  for _cand in $(ls -d "$SDK/ndk/"* 2>/dev/null | sort -Vr); do
    if [[ -f "$_cand/build/cmake/android.toolchain.cmake" ]]; then NDK="$_cand"; break; fi
  done
fi
[[ -n "${NDK:-}" && -f "${NDK:-}/build/cmake/android.toolchain.cmake" ]] || { err "Android NDK not found (set NDK= to a complete install)"; exit 1; }
HOSTTAG="$(ls -d "$NDK/toolchains/llvm/prebuilt/"* | head -1)"
TOOLBIN="$HOSTTAG/bin"
NCPU="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"
export FLUTTER_ROOT="${FLUTTER_ROOT:-$(cd "$(dirname "$(command -v flutter)")/.." && pwd)}"
info "NDK=$NDK  api=$ANDROID_API  ABIS='$ABIS'"

# ABI -> autotools host triple + clang basename prefix
host_for() { case "$1" in
  arm64-v8a)    echo "aarch64-linux-android" ;;
  x86_64)       echo "x86_64-linux-android" ;;
  armeabi-v7a)  echo "armv7a-linux-androideabi" ;;
  x86)          echo "i686-linux-android" ;;
  *) err "unknown ABI $1"; exit 1 ;; esac; }
cc_for()   { case "$1" in
  arm64-v8a)    echo "aarch64-linux-android${ANDROID_API}-clang" ;;
  x86_64)       echo "x86_64-linux-android${ANDROID_API}-clang" ;;
  armeabi-v7a)  echo "armv7a-linux-androideabi${ANDROID_API}-clang" ;;
  x86)          echo "i686-linux-android${ANDROID_API}-clang" ;;
  esac; }

build_abi() {
  local abi="$1"
  local host; host="$(host_for "$abi")"
  local cc="$TOOLBIN/$(cc_for "$abi")"
  local base="$TIM2TOX_DIR/build/android-${abi}"
  local dep_prefix="$base/deps-prefix"
  local ffi_build="$base/ffi-build"
  local src="$base/src"
  mkdir -p "$base" "$src"

  # --- libsodium (static) ---
  if [[ -f "$dep_prefix/lib/libsodium.a" ]]; then
    info "[$abi] libsodium cached"
  else
    info "[$abi] building libsodium $SODIUM_VERSION ..."
    ( cd "$src"
      local tarball="libsodium-${SODIUM_VERSION}.tar.gz"
      if [[ ! -f "$tarball" ]]; then
        curl -fLsS --retry 3 --retry-delay 2 --connect-timeout 30 -o "$tarball" \
          "https://github.com/jedisct1/libsodium/releases/download/${SODIUM_VERSION}-RELEASE/libsodium-${SODIUM_VERSION}.tar.gz" \
          || curl -fLsS -o "$tarball" "https://download.libsodium.org/libsodium/releases/libsodium-${SODIUM_VERSION}-stable.tar.gz"
      fi
      rm -rf extract && mkdir extract && tar xzf "$tarball" -C extract
      local sdir; sdir="$(dirname "$(find "$src/extract" -name configure -maxdepth 2 | head -1)")"
      cd "$sdir"
      ./configure --host="$host" --prefix="$dep_prefix" --enable-static --disable-shared \
        CC="$cc" AR="$TOOLBIN/llvm-ar" RANLIB="$TOOLBIN/llvm-ranlib" \
        STRIP="$TOOLBIN/llvm-strip" CFLAGS="-O2 -fPIC" \
        >"$base/libsodium-configure.log" 2>&1
      make -j"$NCPU" >"$base/libsodium-make.log" 2>&1
      make install >>"$base/libsodium-make.log" 2>&1
    )
  fi

  # --- ToxAV media deps (opus + vpx, shared pinned-source builder) ---
  local toxav_on="ON"
  if [[ "$TOXAV" == "1" ]]; then
    bash "$SCRIPT_DIR/ci/build_av_deps.sh" \
      --platform android --abi "$abi" --ndk "$NDK" --api "$ANDROID_API" \
      --prefix "$dep_prefix" \
      --downloads "$TIM2TOX_DIR/build/mobile-deps/downloads" || { err "[$abi] AV deps build failed"; exit 1; }
  else
    toxav_on="OFF"
    warn "[$abi] TOXAV=0 — building calling-stub variant"
  fi

  # --- toxcore + FFI shim ---
  info "[$abi] configuring + building tim2tox_ffi (TOXAV=$toxav_on) ..."
  PKG_CONFIG_PATH="$dep_prefix/lib/pkgconfig" PKG_CONFIG_LIBDIR="$dep_prefix/lib/pkgconfig" \
  PKG_CONFIG_SYSROOT_DIR="" \
  cmake -S "$TIM2TOX_DIR" -B "$ffi_build" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" \
    -DANDROID_PLATFORM="android-${ANDROID_API}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DSTRICT_ABI=OFF -DBOOTSTRAP_DAEMON=OFF -DBUILD_TOXAV="$toxav_on" -DMUST_BUILD_TOXAV="$toxav_on" \
    -DDHT_BOOTSTRAP=OFF -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
    -DUNITTEST=OFF -DAUTOTEST=OFF -DBUILD_MISC_TESTS=OFF -DBUILD_FUN_UTILS=OFF \
    -DBUILD_FUZZ_TESTS=OFF -DUSE_IPV6=ON -DEXPERIMENTAL_API=OFF -DBUILD_FFI=ON \
    -DTIM2TOX_DISABLE_SQLITE=ON \
    -DTIM2TOX_DEP_PREFIX="$dep_prefix" -DCMAKE_PREFIX_PATH="$dep_prefix" \
    -DCMAKE_FIND_ROOT_PATH="$dep_prefix" \
    >"$base/cmake-configure.log" 2>&1 || { err "[$abi] cmake configure failed"; tail -30 "$base/cmake-configure.log" >&2; exit 1; }
  cmake --build "$ffi_build" --target tim2tox_ffi -j"$NCPU" \
    >"$base/cmake-build.log" 2>&1 || { err "[$abi] cmake build failed"; tail -35 "$base/cmake-build.log" >&2; exit 1; }

  local so; so="$(find "$ffi_build" -name 'libtim2tox_ffi.so' -type f | head -1)"
  [[ -n "$so" ]] || { err "[$abi] no libtim2tox_ffi.so produced"; exit 1; }
  mkdir -p "$JNI_LIBS/$abi"
  cp "$so" "$JNI_LIBS/$abi/libtim2tox_ffi.so"
  "$TOOLBIN/llvm-strip" --strip-unneeded "$JNI_LIBS/$abi/libtim2tox_ffi.so" 2>/dev/null || true
  echo "$so"
}

for abi in $ABIS; do
  so="$(build_abi "$abi")"
  info "[$abi] -> $JNI_LIBS/$abi/libtim2tox_ffi.so"
  echo -e "${CYAN}--- $abi verification ---${NC}" >&2
  file "$JNI_LIBS/$abi/libtim2tox_ffi.so" >&2
  # Dart_PostCObject_DL is an *internal* symbol (used within the .so, populated
  # by Dart_InitializeApiDL), so it is stripped from the jniLibs copy and never
  # in .dynsym — check the unstripped build artifact ($so) with full nm instead.
  # Captured symbol tables (no `nm | grep -q` pipeline — grep -q's early exit
  # SIGPIPEs nm and pipefail turns that into a false negative).
  full_syms="$("$TOOLBIN/llvm-nm" "$so" 2>/dev/null || true)"
  dyn_syms="$("$TOOLBIN/llvm-nm" -D "$JNI_LIBS/$abi/libtim2tox_ffi.so" 2>/dev/null || true)"
  if [[ "$full_syms" == *Dart_PostCObject_DL* ]]; then
    info "[$abi] Dart_PostCObject_DL present (dart_api_dl compiled in)"
  else
    warn "[$abi] Dart_PostCObject_DL NOT found"
  fi
  # The exported Dart* entrypoints (binary-replacement ABI) must survive strip.
  if [[ "$dyn_syms" == *" T DartInitSDK"* ]]; then
    info "[$abi] exported Dart* entrypoints present"
  else
    warn "[$abi] exported Dart* entrypoints MISSING after strip"
  fi
  # ToxAV must be REAL when requested — the marker symbol only exists under
  # BUILD_TOXAV (stub builds silently no-op every call API otherwise).
  if [[ "$TOXAV" == "1" ]]; then
    if [[ "$dyn_syms" == *tim2tox_ffi_av_backend_toxav* ]]; then
      info "[$abi] ToxAV backend confirmed (marker symbol present)"
    else
      err "[$abi] ToxAV requested but marker symbol missing — calling would be a stub"; exit 1
    fi
  fi
done

info "DONE. jniLibs:"
ls -1 "$JNI_LIBS"/*/libtim2tox_ffi.so >&2 2>/dev/null || true
echo -e "${GREEN}[android-ffi] DONE${NC}" >&2
