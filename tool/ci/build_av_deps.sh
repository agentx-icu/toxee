#!/usr/bin/env bash
#
# build_av_deps.sh — cross-compile the ToxAV media dependencies (libopus +
# libvpx, static) into a dependency prefix, for Android (NDK) and iOS
# (iphoneos / iphonesimulator) targets.
#
# This is the single shared implementation used by:
#   * tool/ci/build_tim2tox.sh        (CI + release builds, --target android/ios)
#   * tool/build_android_ffi.sh       (developer loop, per-ABI jniLibs)
#   * tool/build_ios_sim_ffi.sh       (developer loop, simulator universal dylib)
# Keep it dependency-free (bash + curl + make + perl) and idempotent: when the
# prefix already contains both static libs + pkg-config files it exits 0
# without rebuilding.
#
# Desktop platforms do NOT use this script: Linux/macOS resolve opus/vpx from
# system packages (apt/brew) and Windows from vcpkg.
#
# Usage:
#   build_av_deps.sh --platform android --abi <arm64-v8a|armeabi-v7a|x86_64|x86> \
#                    --ndk <path> [--api 21] --prefix <dir> --downloads <dir>
#   build_av_deps.sh --platform ios --sdk <iphoneos|iphonesimulator> \
#                    --arch <arm64|x86_64> [--min-version 13.0] --prefix <dir> --downloads <dir>
#
# x86-family targets normally need yasm/nasm for the libvpx assembly. When
# neither is installed the script falls back to libvpx's C-only `generic-gnu`
# target (slower, but functionally identical) and prints a warning — x86 is
# only used for emulators/simulators, never for shipping device binaries.
set -euo pipefail

# Pinned release tarballs. opus SHA-256 cross-checked against
# https://downloads.xiph.org/releases/opus/SHA256SUMS.txt (2026-07-09).
# libvpx is a GitHub tag archive (upstream publishes no checksums for these);
# the pin below was recorded on first download (2026-07-09) and any later
# mismatch must be treated as tampering until proven otherwise.
OPUS_VERSION="1.5.2"
OPUS_SHA256="65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1"
OPUS_URL="https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz"
VPX_VERSION="1.15.2"
VPX_SHA256="26fcd3db88045dee380e581862a6ef106f49b74b6396ee95c2993a260b4636aa"
VPX_URL="https://github.com/webmproject/libvpx/archive/refs/tags/v${VPX_VERSION}.tar.gz"

PLATFORM=""
ABI=""
NDK_PATH=""
API="21"
IOS_SDK=""
IOS_ARCH=""
IOS_MIN="13.0"
PREFIX=""
DOWNLOADS=""

die() { echo "[av-deps] ERROR: $*" >&2; exit 1; }
log() { echo "[av-deps] $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)    PLATFORM="${2:-}"; shift 2 ;;
    --abi)         ABI="${2:-}"; shift 2 ;;
    --ndk)         NDK_PATH="${2:-}"; shift 2 ;;
    --api)         API="${2:-}"; shift 2 ;;
    --sdk)         IOS_SDK="${2:-}"; shift 2 ;;
    --arch)        IOS_ARCH="${2:-}"; shift 2 ;;
    --min-version) IOS_MIN="${2:-}"; shift 2 ;;
    --prefix)      PREFIX="${2:-}"; shift 2 ;;
    --downloads)   DOWNLOADS="${2:-}"; shift 2 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -n "$PLATFORM" ]] || die "--platform is required (android|ios)"
[[ -n "$PREFIX" ]] || die "--prefix is required"
[[ -n "$DOWNLOADS" ]] || die "--downloads is required"

have_all_artifacts() {
  [[ -f "$PREFIX/lib/libopus.a" && -f "$PREFIX/lib/pkgconfig/opus.pc" && \
     -f "$PREFIX/lib/libvpx.a" && -f "$PREFIX/lib/pkgconfig/vpx.pc" ]]
}

if have_all_artifacts; then
  log "opus+vpx already present in $PREFIX — skipping"
  exit 0
fi

NCPU="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"
mkdir -p "$DOWNLOADS" "$PREFIX"

download_once() {
  local url="$1" dest="$2"
  if [[ ! -f "$dest" ]]; then
    log "downloading $(basename "$dest")"
    curl -fLsS --retry 3 --retry-delay 2 --connect-timeout 30 -o "$dest" "$url" || \
      die "download failed: $url"
  fi
}

verify_sha256() {
  local path="$1" expected="$2"
  local actual=""
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$path" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$path" | awk '{print $1}')"
  else
    die "no sha256sum/shasum available"
  fi
  if [[ "$actual" != "$expected" ]]; then
    rm -f "$path"
    die "$(basename "$path"): sha256 mismatch (got $actual, expected $expected). File removed; re-run to re-download."
  fi
}

extract_to() {
  local tarball="$1" destdir="$2"
  rm -rf "$destdir"
  mkdir -p "$destdir"
  tar -xzf "$tarball" -C "$destdir"
}

# ---------------------------------------------------------------------------
# Toolchain resolution
# ---------------------------------------------------------------------------
CC_BIN="" CXX_BIN="" AR_BIN="" RANLIB_BIN="" STRIP_BIN="" AS_BIN=""
OPUS_HOST="" OPUS_CFLAGS="-O2 -fPIC" OPUS_LDFLAGS=""
VPX_TARGET="" VPX_EXTRA_CFLAGS="-O2 -fPIC"

case "$PLATFORM" in
  android)
    [[ -n "$ABI" ]] || die "--abi is required for android"
    [[ -n "$NDK_PATH" && -d "$NDK_PATH" ]] || die "--ndk path missing or invalid: $NDK_PATH"
    # Host-agnostic prebuilt dir (linux-x86_64 on CI, darwin-x86_64 on Macs).
    TOOLBIN="$(ls -d "$NDK_PATH/toolchains/llvm/prebuilt/"*/bin 2>/dev/null | head -n 1)"
    [[ -n "$TOOLBIN" ]] || die "NDK llvm prebuilt toolchain not found under $NDK_PATH"
    case "$ABI" in
      arm64-v8a)   OPUS_HOST="aarch64-linux-android";  CC_NAME="aarch64-linux-android${API}-clang";  VPX_TARGET="arm64-android-gcc" ;;
      armeabi-v7a) OPUS_HOST="armv7a-linux-androideabi"; CC_NAME="armv7a-linux-androideabi${API}-clang"; VPX_TARGET="armv7-android-gcc" ;;
      x86_64)      OPUS_HOST="x86_64-linux-android";   CC_NAME="x86_64-linux-android${API}-clang";   VPX_TARGET="x86_64-android-gcc" ;;
      x86)         OPUS_HOST="i686-linux-android";     CC_NAME="i686-linux-android${API}-clang";     VPX_TARGET="x86-android-gcc" ;;
      *) die "Unsupported Android ABI: $ABI" ;;
    esac
    CC_BIN="$TOOLBIN/$CC_NAME"
    CXX_BIN="$TOOLBIN/${CC_NAME}++"
    AR_BIN="$TOOLBIN/llvm-ar"
    RANLIB_BIN="$TOOLBIN/llvm-ranlib"
    STRIP_BIN="$TOOLBIN/llvm-strip"
    AS_BIN="$CC_BIN"
    [[ -x "$CC_BIN" ]] || die "NDK clang not found: $CC_BIN"
    ;;
  ios)
    [[ "$OSTYPE" == darwin* ]] || die "iOS deps can only be built on macOS"
    [[ -n "$IOS_SDK" && -n "$IOS_ARCH" ]] || die "--sdk and --arch are required for ios"
    SYSROOT="$(xcrun --sdk "$IOS_SDK" --show-sdk-path)"
    CC_BIN="$(xcrun --sdk "$IOS_SDK" --find clang)"
    CXX_BIN="$(xcrun --sdk "$IOS_SDK" --find clang++)"
    AR_BIN="$(xcrun --sdk "$IOS_SDK" --find ar)"
    RANLIB_BIN="$(xcrun --sdk "$IOS_SDK" --find ranlib)"
    STRIP_BIN="$(xcrun --sdk "$IOS_SDK" --find strip)"
    AS_BIN="$CC_BIN"
    local_triple_flags=""
    if [[ "$IOS_SDK" == "iphonesimulator" ]]; then
      local_triple_flags="-target ${IOS_ARCH}-apple-ios${IOS_MIN}-simulator -isysroot $SYSROOT"
      case "$IOS_ARCH" in
        # libvpx (<=1.15.x) has no arm64-iphonesimulator target, and the
        # arm64-darwin*/arm64-darwin-gcc targets inject macOS/iphoneos
        # deployment flags that clash with the simulator -target triple.
        # generic-gnu compiles C-only (no NEON asm) and takes our flags
        # verbatim — acceptable for the simulator, which is a dev-only
        # surface; device slices keep the full-speed arm64-darwin-gcc.
        arm64)  VPX_TARGET="generic-gnu" ;;
        x86_64) VPX_TARGET="x86_64-iphonesimulator-gcc" ;;
        *) die "Unsupported iOS simulator arch: $IOS_ARCH" ;;
      esac
    else
      local_triple_flags="-arch ${IOS_ARCH} -isysroot $SYSROOT -miphoneos-version-min=${IOS_MIN}"
      case "$IOS_ARCH" in
        arm64) VPX_TARGET="arm64-darwin-gcc" ;;
        *) die "Unsupported iOS device arch: $IOS_ARCH" ;;
      esac
    fi
    case "$IOS_ARCH" in
      arm64)  OPUS_HOST="aarch64-apple-darwin" ;;
      x86_64) OPUS_HOST="x86_64-apple-darwin" ;;
    esac
    OPUS_CFLAGS="$local_triple_flags -O2"
    OPUS_LDFLAGS="$local_triple_flags"
    VPX_EXTRA_CFLAGS="$local_triple_flags -O2"
    ;;
  *)
    die "Unsupported platform: $PLATFORM"
    ;;
esac

# x86-family libvpx assembly needs yasm/nasm; fall back to C-only generic-gnu.
case "$VPX_TARGET" in
  x86*-*)
    if ! command -v yasm >/dev/null 2>&1 && ! command -v nasm >/dev/null 2>&1; then
      log "WARNING: yasm/nasm not found — building libvpx C-only (generic-gnu) for $VPX_TARGET."
      log "         Install yasm (brew install yasm / apt install yasm) for optimized x86 builds."
      VPX_TARGET="generic-gnu"
    fi
    ;;
esac

# ---------------------------------------------------------------------------
# opus (autotools)
# ---------------------------------------------------------------------------
build_opus() {
  if [[ -f "$PREFIX/lib/libopus.a" && -f "$PREFIX/lib/pkgconfig/opus.pc" ]]; then
    log "opus cached in $PREFIX"
    return 0
  fi
  local tarball="$DOWNLOADS/opus-${OPUS_VERSION}.tar.gz"
  local src_root="$PREFIX-src/opus"
  download_once "$OPUS_URL" "$tarball"
  verify_sha256 "$tarball" "$OPUS_SHA256"
  extract_to "$tarball" "$src_root"
  log "building opus ${OPUS_VERSION} for $PLATFORM ${ABI:-$IOS_SDK/$IOS_ARCH}"
  (
    cd "$src_root/opus-${OPUS_VERSION}"
    ./configure \
      --host="$OPUS_HOST" \
      --prefix="$PREFIX" \
      --enable-static --disable-shared \
      --disable-extra-programs --disable-doc \
      CC="$CC_BIN" AR="$AR_BIN" RANLIB="$RANLIB_BIN" STRIP="$STRIP_BIN" \
      CFLAGS="$OPUS_CFLAGS" LDFLAGS="$OPUS_LDFLAGS" \
      > configure.log 2>&1 || { tail -30 configure.log >&2; exit 1; }
    make -j"$NCPU" > make.log 2>&1 || { tail -30 make.log >&2; exit 1; }
    make install >> make.log 2>&1
  )
  [[ -f "$PREFIX/lib/libopus.a" ]] || die "opus build produced no libopus.a"
}

# ---------------------------------------------------------------------------
# libvpx (custom configure; needs perl)
# ---------------------------------------------------------------------------
build_vpx() {
  if [[ -f "$PREFIX/lib/libvpx.a" && -f "$PREFIX/lib/pkgconfig/vpx.pc" ]]; then
    log "libvpx cached in $PREFIX"
    return 0
  fi
  command -v perl >/dev/null 2>&1 || die "libvpx build requires perl"
  local tarball="$DOWNLOADS/libvpx-${VPX_VERSION}.tar.gz"
  local src_root="$PREFIX-src/libvpx"
  download_once "$VPX_URL" "$tarball"
  verify_sha256 "$tarball" "$VPX_SHA256"
  extract_to "$tarball" "$src_root"
  log "building libvpx ${VPX_VERSION} (target=$VPX_TARGET) for $PLATFORM ${ABI:-$IOS_SDK/$IOS_ARCH}"
  (
    cd "$src_root/libvpx-${VPX_VERSION}"
    mkdir -p build-out && cd build-out
    # libvpx's configure reads the toolchain from the environment; LD must be
    # the C driver (not ld) so cross linking gets the right sysroot flags.
    local vpx_cc="$CC_BIN" vpx_cxx="$CXX_BIN"
    if [[ "$VPX_TARGET" == "generic-gnu" && "$PLATFORM" == "ios" ]]; then
      # generic-gnu injects no target/sysroot flags of its own, and configure's
      # check_ld links WITHOUT --extra-cflags — a bare host link against an
      # iOS-simulator object fails (ld: library 'c++' not found). Embed the
      # triple flags into the tool variables; libvpx word-splits them.
      vpx_cc="$CC_BIN $local_triple_flags"
      vpx_cxx="$CXX_BIN $local_triple_flags"
    fi
    export CC="$vpx_cc" CXX="$vpx_cxx" AR="$AR_BIN" RANLIB="$RANLIB_BIN" \
           STRIP="$STRIP_BIN" AS="$vpx_cc" LD="$vpx_cc"
    ../configure \
      --target="$VPX_TARGET" \
      --prefix="$PREFIX" \
      --enable-static --disable-shared --enable-pic \
      --enable-vp8 --enable-vp9 \
      --disable-examples --disable-tools --disable-docs --disable-unit-tests \
      --disable-install-bins --disable-install-docs \
      --disable-werror \
      --extra-cflags="$VPX_EXTRA_CFLAGS" \
      > configure.log 2>&1 || { tail -30 configure.log >&2; exit 1; }
    make -j"$NCPU" > make.log 2>&1 || { tail -30 make.log >&2; exit 1; }
    make install >> make.log 2>&1
  )
  [[ -f "$PREFIX/lib/libvpx.a" ]] || die "libvpx build produced no libvpx.a"
}

build_opus
build_vpx
log "opus+vpx ready in $PREFIX"
