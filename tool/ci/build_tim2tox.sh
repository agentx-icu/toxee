#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tool/ci/common.sh
source "$SCRIPT_DIR/common.sh"

# Pinned SHA-256 of the libsodium 1.0.20 release tarball
# (https://github.com/jedisct1/libsodium/releases/tag/1.0.20-RELEASE).
# Treat any mismatch as a hard failure — libsodium is the crypto floor,
# silent CDN poisoning here breaks message confidentiality (F6).
LIBSODIUM_1_0_20_SHA256="ebb65ef6ca439333c2bb41a0c1990587288da07f6c7fd07cb3a18cc18d30ce19"

TARGET=""
MODE="release"
WINDOWS_ARCH="${TIM2TOX_WINDOWS_ARCH:-x64}" # x64|arm64
# ToxAV (calling) is ON by default with MUST_BUILD_TOXAV mirroring it, so a
# missing opus/vpx is a HARD configure error instead of a silent feature drop.
# History: ToxAV used to be opt-in via --toxav and every production entry
# point (build-packages.yml, all five targets) forgot to pass it — every
# shipped artifact had calling stubbed out. Default-on + fail-loud makes that
# regression impossible. Use --no-toxav ONLY for builds that intentionally
# stub calling (lean test tiers).
ENABLE_TOXAV=1
ENABLE_DHT_BOOTSTRAP=0
ENABLE_IRC=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --toxav)
      # Back-compat: ToxAV is already the default; kept so existing CI
      # invocations remain valid.
      ENABLE_TOXAV=1
      shift
      ;;
    --no-toxav)
      ENABLE_TOXAV=0
      shift
      ;;
    --dht-bootstrap)
      ENABLE_DHT_BOOTSTRAP=1
      shift
      ;;
    --with-irc)
      # Desktop targets only: also build + capture libirc_client (the
      # on-demand IRC application library; see ffi/CMakeLists.txt).
      ENABLE_IRC=1
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage: build_tim2tox.sh --target <linux|windows|macos|android|ios>
                        [--mode <debug|profile|release>]
                        [--no-toxav]
                        [--dht-bootstrap]

Options:
  --target          Build target (required).
  --mode            Build mode (default: release).
  --no-toxav        Disable BUILD_TOXAV/MUST_BUILD_TOXAV (default: ON).
                    Calling becomes a no-op stub — never use for artifacts
                    that ship to users. (--toxav is accepted as a no-op for
                    back-compat.)
  --dht-bootstrap   Enable DHT_BOOTSTRAP/BOOTSTRAP_DAEMON (default: off).
                    Required by auto_tests using local bootstrap nodes.
  --with-irc        Also build + capture libirc_client (desktop targets).
                    Needs OpenSSL: linux `apt install libssl-dev`,
                    windows `vcpkg install openssl:<triplet>`, macos brew.

Dependencies when ToxAV is on:
  linux:   apt install libopus-dev libvpx-dev
  macos:   brew install opus libvpx
  windows: vcpkg install opus:<triplet> libvpx:<triplet>
  android/ios: built from pinned sources automatically (tool/ci/build_av_deps.sh)
EOF
      exit 0
      ;;
    *)
      ci_die "Unknown option: $1"
      ;;
  esac
done

[[ -n "$TARGET" ]] || ci_die "--target is required"

REPO_ROOT="$(ci_repo_root)"
TIM2TOX_DIR="$REPO_ROOT/third_party/tim2tox"
# Out-of-tree build support: when the checkout lives on a read-only or slow
# network mount (e.g. a Parallels/VM shared folder), the source tree cannot
# hold build dirs. Override these to keep sources in place and write all
# build state + artifacts to a local disk. Defaults preserve the historical
# in-tree layout.
TIM2TOX_BUILD_ROOT="${TIM2TOX_NATIVE_BUILD_ROOT:-$TIM2TOX_DIR/build}"
OUTPUT_DIR="${TOXEE_NATIVE_ARTIFACTS_DIR:-$REPO_ROOT/build/native-artifacts}/$TARGET"

[[ -d "$TIM2TOX_DIR" ]] || ci_die "tim2tox submodule not found: $TIM2TOX_DIR"

# Preserve previously built OPTIONAL IRC artifacts across a non-IRC rebuild:
# launchers rebuild the FFI on demand WITHOUT --with-irc, and a plain reset
# would silently delete libirc_client + its OpenSSL runtime (staged earlier by
# a --with-irc build), breaking the live IRC JOIN scenarios.
_irc_stash=""
if [[ "$ENABLE_IRC" -ne 1 ]] && compgen -G "$OUTPUT_DIR/libirc_client.*" > /dev/null 2>&1; then
  _irc_stash="$(mktemp -d)"
  cp -a "$OUTPUT_DIR"/libirc_client.* "$_irc_stash/" 2>/dev/null || true
  cp -a "$OUTPUT_DIR"/libssl* "$_irc_stash/" 2>/dev/null || true
  cp -a "$OUTPUT_DIR"/libcrypto* "$_irc_stash/" 2>/dev/null || true
fi
ci_reset_dir "$OUTPUT_DIR"
if [[ -n "$_irc_stash" ]]; then
  cp -a "$_irc_stash"/. "$OUTPUT_DIR/" 2>/dev/null || true
  rm -rf "$_irc_stash"
  ci_log "Preserved previously built IRC artifacts across a non-IRC rebuild"
fi

bootstrap_tim2tox_submodules() {
  if [[ -f "$TIM2TOX_DIR/.gitmodules" ]] && { [[ -d "$TIM2TOX_DIR/.git" ]] || [[ -f "$TIM2TOX_DIR/.git" ]]; }; then
    ci_log "Ensuring tim2tox nested submodules are initialized"
    if ! (cd "$TIM2TOX_DIR" && git submodule update --init --recursive); then
      # Non-fatal when the sources are already checked out: a worktree
      # accessed over a VM shared-folder mount has a .git file whose gitdir
      # points at a host-only absolute path, so git commands fail even
      # though the tree is complete.
      if [[ -f "$TIM2TOX_DIR/third_party/c-toxcore/CMakeLists.txt" ]]; then
        ci_warn "git submodule update failed but c-toxcore sources are present — continuing (read-only/mounted checkout)"
      else
        ci_die "git submodule update failed and c-toxcore sources are missing"
      fi
    fi
  fi
}

capture_linux_shared_library() {
  local library_path="$1"
  [[ -n "$library_path" && -e "$library_path" ]] || return 0

  local resolved_path
  resolved_path="$(readlink -f "$library_path" 2>/dev/null || printf '%s\n' "$library_path")"

  cp -P "$library_path" "$OUTPUT_DIR/"
  if [[ "$resolved_path" != "$library_path" && -f "$resolved_path" ]]; then
    cp "$resolved_path" "$OUTPUT_DIR/"
  fi
}

configure_args=(
  -DBUILD_FFI=ON
  -DBUILD_TOXAV=OFF
  -DMUST_BUILD_TOXAV=OFF
  -DDHT_BOOTSTRAP=OFF
  -DBOOTSTRAP_DAEMON=OFF
  -DENABLE_SHARED=OFF
  -DENABLE_STATIC=ON
  -DUNITTEST=OFF
  -DAUTOTEST=OFF
  -DBUILD_MISC_TESTS=OFF
  -DBUILD_FUN_UTILS=OFF
  -DBUILD_FUZZ_TESTS=OFF
  -DUSE_IPV6=ON
  -DEXPERIMENTAL_API=OFF
  -DERROR=ON
  -DWARNING=ON
  -DINFO=ON
  -DTRACE=OFF
  -DDEBUG=OFF
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
)

# Replace existing OFF entries in-place (don't append duplicates) so the
# upstream defaults stay authoritative and the toggles only flip a single
# value. Mirror BUILD_TOXAV with MUST_BUILD_TOXAV and DHT_BOOTSTRAP with
# BOOTSTRAP_DAEMON — auto_tests need both halves of each pair.
set_configure_arg() {
  local key="$1"
  local value="$2"
  local i
  for i in "${!configure_args[@]}"; do
    case "${configure_args[$i]}" in
      -D"${key}"=*)
        configure_args[$i]="-D${key}=${value}"
        return 0
        ;;
    esac
  done
  configure_args+=("-D${key}=${value}")
}

if [[ "$ENABLE_TOXAV" -eq 1 ]]; then
  set_configure_arg "BUILD_TOXAV" "ON"
  set_configure_arg "MUST_BUILD_TOXAV" "ON"
fi

if [[ "$ENABLE_DHT_BOOTSTRAP" -eq 1 ]]; then
  set_configure_arg "DHT_BOOTSTRAP" "ON"
  set_configure_arg "BOOTSTRAP_DAEMON" "ON"
fi

# NDK llvm prebuilt directory, host-agnostic (linux-x86_64 on CI runners,
# darwin-* on developer Macs). The previous hardcoded linux-x86_64 made the
# android target unbuildable on macOS hosts.
android_ndk_toolchain_dir() {
  local ndk_path="$1"
  local dir
  dir="$(ls -d "$ndk_path/toolchains/llvm/prebuilt/"* 2>/dev/null | head -n 1)"
  [[ -n "$dir" ]] || ci_die "NDK llvm prebuilt toolchain not found under $ndk_path"
  printf '%s\n' "$dir"
}

find_android_ndk() {
  local candidate sdk_root latest

  for candidate in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  for sdk_root in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}"; do
    [[ -n "$sdk_root" && -d "$sdk_root" ]] || continue

    if [[ -d "$sdk_root/ndk" ]]; then
      latest="$(find "$sdk_root/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1 || true)"
      if [[ -n "$latest" ]]; then
        printf '%s\n' "$latest"
        return
      fi
    fi

    if [[ -d "$sdk_root/ndk-bundle" ]]; then
      printf '%s\n' "$sdk_root/ndk-bundle"
      return
    fi
  done

  ci_die "Unable to locate Android NDK (checked ANDROID_NDK_HOME, ANDROID_NDK_ROOT, ANDROID_SDK_ROOT, ANDROID_HOME)"
}

download_file_once() {
  local url="$1"
  local dest="$2"

  if [[ ! -f "$dest" ]]; then
    if command -v curl >/dev/null 2>&1; then
      curl -L --fail --retry 3 --retry-delay 2 -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
      wget -O "$dest" "$url"
    else
      ci_die "Missing curl/wget for downloading $url"
    fi
  fi
}

verify_sha256() {
  local path="$1"
  local expected="$2"
  local label="${3:-$(basename "$path")}"
  local actual=""

  [[ -f "$path" ]] || ci_die "$label: file missing for sha256 verification: $path"

  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$path" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$path" | awk '{print $1}')"
  else
    ci_die "$label: no sha256sum/shasum available to verify $path"
  fi

  if [[ "$actual" != "$expected" ]]; then
    # Remove the poisoned file so a retry doesn't keep re-failing on cached bytes.
    rm -f "$path"
    ci_die "$label: sha256 mismatch (got $actual, expected $expected). File removed; re-run to re-download."
  fi
}

prepare_android_libsodium_prefix() {
  local abi="$1"
  local ndk_path="$2"
  local prefix="$TIM2TOX_BUILD_ROOT/mobile-deps/android-$abi"
  local download_dir="$TIM2TOX_BUILD_ROOT/mobile-deps/downloads"
  local src_root="$TIM2TOX_BUILD_ROOT/mobile-deps/src-android-$abi"
  local archive="$download_dir/libsodium-1.0.20.tar.gz"
  local host target api toolchain sysroot

  if [[ -f "$prefix/lib/libsodium.a" ]]; then
    return
  fi

  case "$abi" in
    arm64-v8a)
      target="aarch64-linux-android"
      api="21"
      ;;
    armeabi-v7a)
      target="armv7a-linux-androideabi"
      api="21"
      ;;
    x86_64)
      target="x86_64-linux-android"
      api="21"
      ;;
    *)
      ci_die "Unsupported Android ABI: $abi"
      ;;
  esac

  toolchain="$(android_ndk_toolchain_dir "$ndk_path")"
  sysroot="$toolchain/sysroot"

  mkdir -p "$download_dir"
  download_file_once \
    "https://github.com/jedisct1/libsodium/releases/download/1.0.20-RELEASE/libsodium-1.0.20.tar.gz" \
    "$archive"
  verify_sha256 "$archive" "$LIBSODIUM_1_0_20_SHA256" "libsodium-1.0.20 (android-$abi)"

  rm -rf "$src_root"
  mkdir -p "$src_root"
  tar -xzf "$archive" -C "$src_root"

  pushd "$src_root/libsodium-1.0.20" >/dev/null
  export CC="$toolchain/bin/${target}${api}-clang"
  export CXX="$toolchain/bin/${target}${api}-clang++"
  export AR="$toolchain/bin/llvm-ar"
  export RANLIB="$toolchain/bin/llvm-ranlib"
  export STRIP="$toolchain/bin/llvm-strip"
  ./configure \
    --prefix="$prefix" \
    --host="$target" \
    --with-sysroot="$sysroot" \
    --disable-shared \
    --disable-pie
  make -j"$(ci_cpu_count)"
  make install
  popd >/dev/null
}

android_libsodium_prefix_path() {
  printf '%s\n' "$TIM2TOX_BUILD_ROOT/mobile-deps/android-$1"
}

build_android_ffi_for_abi() {
  local abi="$1"
  local ndk_path="$2"
  local prefix build_dir built_lib repo_jni_libs toolchain sysroot

  prefix="$(android_libsodium_prefix_path "$abi")"
  prepare_android_libsodium_prefix "$abi" "$ndk_path"
  if [[ "$ENABLE_TOXAV" -eq 1 ]]; then
    bash "$SCRIPT_DIR/build_av_deps.sh" \
      --platform android --abi "$abi" --ndk "$ndk_path" --api 21 \
      --prefix "$prefix" \
      --downloads "$TIM2TOX_BUILD_ROOT/mobile-deps/downloads"
  fi
  build_dir="$TIM2TOX_BUILD_ROOT/ci-android-$abi"
  repo_jni_libs="$REPO_ROOT/android/app/src/main/jniLibs"
  toolchain="$(android_ndk_toolchain_dir "$ndk_path")"
  sysroot="$toolchain/sysroot"

  mkdir -p "$OUTPUT_DIR/jniLibs/$abi"
  export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"

  cmake -S "$TIM2TOX_DIR" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$ndk_path/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" \
    -DANDROID_PLATFORM=21 \
    -DANDROID_STL=c++_shared \
    -DCMAKE_PREFIX_PATH="$prefix" \
    -DTIM2TOX_DEP_PREFIX="$prefix" \
    -DCMAKE_FIND_ROOT_PATH="$prefix;$sysroot" \
    -DCMAKE_C_FLAGS="-Wno-error=format" \
    -DCMAKE_CXX_FLAGS="-Wno-error=deprecated-copy -Wno-error=format" \
    -DTIM2TOX_DISABLE_SQLITE=ON \
    "${configure_args[@]}"

  cmake --build "$build_dir" --config Release --target tim2tox_ffi --parallel "$(ci_cpu_count)"

  built_lib="$(find "$build_dir" -type f -name 'libtim2tox_ffi.so' | head -n 1 || true)"
  [[ -n "$built_lib" ]] || ci_die "Failed to locate Android libtim2tox_ffi.so for ABI $abi"
  cp "$built_lib" "$OUTPUT_DIR/jniLibs/$abi/libtim2tox_ffi.so"
  ci_log "Captured Android native library for $abi: $built_lib"
  assert_toxav_artifact "$OUTPUT_DIR/jniLibs/$abi/libtim2tox_ffi.so" "$toolchain/bin/llvm-nm" "android-$abi"

  rm -rf "$repo_jni_libs"
  mkdir -p "$repo_jni_libs"
  cp -R "$OUTPUT_DIR/jniLibs"/. "$repo_jni_libs/"
}

build_android_ffi_libs() {
  local source_dir="${TIM2TOX_ANDROID_LIB_DIR:-}"
  local repo_jni_libs="$REPO_ROOT/android/app/src/main/jniLibs"
  local ndk_path abi
  local -a android_abis=()

  if [[ -z "$source_dir" ]]; then
    # No `find | grep -q` (pipefail + grep -q early-exit = SIGPIPE false
    # negative); -print -quit stops find after the first hit instead.
    if [[ -d "$repo_jni_libs" && -n "$(find "$repo_jni_libs" -type f -name "libtim2tox_ffi.so" -print -quit)" ]]; then
      source_dir="$repo_jni_libs"
    fi
  fi

  if [[ -n "$source_dir" ]]; then
    [[ -d "$source_dir" ]] || ci_die "TIM2TOX_ANDROID_LIB_DIR is not a directory: $source_dir"
    mkdir -p "$OUTPUT_DIR/jniLibs"
    cp -R "$source_dir"/. "$OUTPUT_DIR/jniLibs/"
    if [[ "$source_dir" != "$repo_jni_libs" ]]; then
      rm -rf "$repo_jni_libs"
      mkdir -p "$repo_jni_libs"
      cp -R "$source_dir"/. "$repo_jni_libs/"
      ci_log "Staged Android JNI libraries into $repo_jni_libs"
    fi
    ci_log "Synced Android JNI libraries from $source_dir"
    while IFS= read -r synced_lib; do
      assert_toxav_artifact "$synced_lib" nm "android-synced"
    done < <(find "$OUTPUT_DIR/jniLibs" -type f -name 'libtim2tox_ffi.so')
    return
  fi

  ndk_path="$(find_android_ndk)"
  if [[ -n "${TIM2TOX_ANDROID_ABIS:-}" ]]; then
    # shellcheck disable=SC2206
    android_abis=(${TIM2TOX_ANDROID_ABIS//,/ })
  else
    android_abis=(arm64-v8a)
  fi

  for abi in "${android_abis[@]}"; do
    build_android_ffi_for_abi "$abi" "$ndk_path"
  done

  ci_log "Built Android Tim2Tox JNI libraries for: ${android_abis[*]}"
}

ios_dependency_prefix_path() {
  printf '%s\n' "$TIM2TOX_BUILD_ROOT/mobile-deps/ios-arm64"
}

prepare_ios_libsodium_prefix() {
  local prefix
  local download_dir="$TIM2TOX_BUILD_ROOT/mobile-deps/downloads"
  local src_root="$TIM2TOX_BUILD_ROOT/mobile-deps/src-ios-arm64"
  local archive="$download_dir/libsodium-1.0.20.tar.gz"
  local sdk_path host

  prefix="$(ios_dependency_prefix_path)"
  if [[ -f "$prefix/lib/libsodium.a" ]]; then
    return
  fi

  mkdir -p "$download_dir"
  download_file_once \
    "https://github.com/jedisct1/libsodium/releases/download/1.0.20-RELEASE/libsodium-1.0.20.tar.gz" \
    "$archive"
  verify_sha256 "$archive" "$LIBSODIUM_1_0_20_SHA256" "libsodium-1.0.20 (ios-arm64)"

  rm -rf "$src_root"
  mkdir -p "$src_root"
  tar -xzf "$archive" -C "$src_root"

  sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
  host="arm-apple-darwin"

  pushd "$src_root/libsodium-1.0.20" >/dev/null
  export CC="$(xcrun --sdk iphoneos --find clang)"
  export CXX="$(xcrun --sdk iphoneos --find clang++)"
  export AR="$(xcrun --sdk iphoneos --find ar)"
  export RANLIB="$(xcrun --sdk iphoneos --find ranlib)"
  export STRIP="$(xcrun --sdk iphoneos --find strip)"
  export CFLAGS="-arch arm64 -isysroot $sdk_path -miphoneos-version-min=13.0"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="$CFLAGS"
  ./configure \
    --prefix="$prefix" \
    --host="$host" \
    --disable-shared \
    --disable-pie
  make -j"$(ci_cpu_count)"
  make install
  popd >/dev/null
}

build_ios_ffi_dylib() {
  local prefix build_dir sdk_path built_lib framework_dir

  prefix="$(ios_dependency_prefix_path)"
  prepare_ios_libsodium_prefix
  if [[ "$ENABLE_TOXAV" -eq 1 ]]; then
    bash "$SCRIPT_DIR/build_av_deps.sh" \
      --platform ios --sdk iphoneos --arch arm64 --min-version 13.0 \
      --prefix "$prefix" \
      --downloads "$TIM2TOX_BUILD_ROOT/mobile-deps/downloads"
  fi
  build_dir="$TIM2TOX_BUILD_ROOT/ci-ios-arm64"
  sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
  export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"

  cmake -S "$TIM2TOX_DIR" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sdk_path" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_C_COMPILER="$(xcrun --sdk iphoneos --find clang)" \
    -DCMAKE_CXX_COMPILER="$(xcrun --sdk iphoneos --find clang++)" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_PREFIX_PATH="$prefix" \
    -DTIM2TOX_DEP_PREFIX="$prefix" \
    -DCMAKE_C_FLAGS="-miphoneos-version-min=13.0 -arch arm64 -Wno-error=format" \
    -DCMAKE_CXX_FLAGS="-miphoneos-version-min=13.0 -arch arm64 -Wno-error=deprecated-copy -Wno-error=format" \
    -DCMAKE_EXE_LINKER_FLAGS="-miphoneos-version-min=13.0 -arch arm64" \
    -DCMAKE_SHARED_LINKER_FLAGS="-miphoneos-version-min=13.0 -arch arm64" \
    -DTIM2TOX_DISABLE_SQLITE=ON \
    "${configure_args[@]}"

  cmake --build "$build_dir" --config Release --target tim2tox_ffi --parallel "$(ci_cpu_count)"

  built_lib="$(find "$build_dir" -type f -name 'libtim2tox_ffi.dylib' | head -n 1 || true)"
  [[ -n "$built_lib" ]] || ci_die "Failed to locate iOS libtim2tox_ffi.dylib"

  framework_dir="$OUTPUT_DIR/tim2tox_ffi.framework"
  rm -rf "$framework_dir"
  mkdir -p "$framework_dir"
  cp "$built_lib" "$framework_dir/tim2tox_ffi"
  assert_toxav_artifact "$framework_dir/tim2tox_ffi" nm "ios-arm64"
  cat > "$framework_dir/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>tim2tox_ffi</string>
  <key>CFBundleIdentifier</key>
  <string>org.toxee.tim2tox_ffi</string>
  <key>CFBundleName</key>
  <string>tim2tox_ffi</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>MinimumOSVersion</key>
  <string>13.0</string>
</dict>
</plist>
EOF
  ci_log "Captured iOS framework from $built_lib"
}

# Assert a built artifact really contains the ToxAV backend (not the stub).
# The marker symbol tim2tox_ffi_av_backend_toxav is only compiled+exported
# under BUILD_TOXAV — see ffi/tim2tox_ffi.cpp. Cross-compiled artifacts can't
# be executed on the build host, so this is a symbol-table check.
#   $1 = library path, $2 = optional nm tool (defaults to `nm`), $3 = label
assert_toxav_artifact() {
  local lib="$1"
  local nm_tool="${2:-nm}"
  local label="${3:-$(basename "$lib")}"
  [[ "$ENABLE_TOXAV" -eq 1 ]] || return 0
  [[ -f "$lib" ]] || ci_die "$label: artifact missing for ToxAV assertion: $lib"

  # No `nm | grep -q` pipeline here: grep -q exits on first match, nm gets
  # SIGPIPE, and under `set -o pipefail` the whole pipeline turns non-zero —
  # a false "symbol missing". Capture the symbol table instead.
  local syms=""
  if command -v "$nm_tool" >/dev/null 2>&1; then
    syms="$({ "$nm_tool" -D "$lib" 2>/dev/null; "$nm_tool" -g "$lib" 2>/dev/null; } || true)"
  fi
  if [[ -n "$syms" ]]; then
    if [[ "$syms" == *tim2tox_ffi_av_backend_toxav* ]]; then
      ci_log "$label: ToxAV backend confirmed (marker symbol present)"
      return 0
    fi
    ci_die "$label: built with ToxAV requested but marker symbol tim2tox_ffi_av_backend_toxav is MISSING — calling would be a stub. Aborting."
  fi
  # nm unavailable (Windows Git Bash) or unable to parse this file format:
  # export/symbol names are stored as ASCII in ELF/PE/Mach-O tables, so a
  # binary grep is a serviceable fallback.
  if grep -aq "tim2tox_ffi_av_backend_toxav" "$lib"; then
    ci_log "$label: ToxAV backend confirmed (export-name grep)"
    return 0
  fi
  ci_die "$label: built with ToxAV requested but marker export tim2tox_ffi_av_backend_toxav is MISSING — calling would be a stub. Aborting."
}

build_desktop_target() {
  local target="$1"
  local build_dir="$TIM2TOX_BUILD_ROOT/ci-$target"
  local lib_pattern=""
  local built_lib=""

  if [[ "$ENABLE_IRC" -eq 1 ]]; then
    configure_args+=(-DTIM2TOX_BUILD_IRC=ON)
  fi

  bootstrap_tim2tox_submodules
  mkdir -p "$build_dir"

  case "$target" in
    linux)
      lib_pattern="libtim2tox_ffi.so"
      ci_log "Configuring tim2tox for Linux"
      cmake -S "$TIM2TOX_DIR" -B "$build_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="-Wno-error=deprecated-copy -Wno-error=format -include arpa/inet.h" \
        -DCMAKE_C_FLAGS="-Wno-error=format" \
        "${configure_args[@]}"
      ;;
    macos)
      lib_pattern="libtim2tox_ffi.dylib"
      ci_log "Configuring tim2tox for macOS"
      cmake -S "$TIM2TOX_DIR" -B "$build_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="-Wno-error=deprecated-copy -Wno-error=format" \
        -DCMAKE_C_FLAGS="-Wno-error=format" \
        "${configure_args[@]}"
      ;;
    windows)
      lib_pattern="tim2tox_ffi.dll"
      ci_log "Configuring tim2tox for Windows"
      local source_dir_win build_dir_win
      source_dir_win="$(ci_windows_path "$TIM2TOX_DIR")"
      build_dir_win="$(ci_windows_path "$build_dir")"
      local vs_arch vcpkg_triplet
      # bash 3.x on macOS doesn't support ${var,,} lowercase expansion.
      local windows_arch_lc
      windows_arch_lc="$(printf "%s" "${WINDOWS_ARCH}" | tr '[:upper:]' '[:lower:]')"
      case "${windows_arch_lc}" in
        arm64)
          vs_arch="arm64"
          vcpkg_triplet="arm64-windows"
          ;;
        x64|*)
          vs_arch="x64"
          vcpkg_triplet="x64-windows"
          ;;
      esac
      # Pick a generator that actually exists on this runner. The windows-2025
      # image now ships Visual Studio 18 (next-gen) rather than VS 17 2022, so
      # hardcoding `-G "Visual Studio 17 2022"` fails with "could not find any
      # instance of Visual Studio." Preference order: env override > Ninja
      # (cross-version, no -A needed since arch comes from vcvars) > VS 18 >
      # VS 17.
      if [[ "$ENABLE_TOXAV" -eq 1 && -n "${VCPKG_ROOT:-}" ]]; then
        local pc_dir="$VCPKG_ROOT/installed/$vcpkg_triplet/lib/pkgconfig"
        [[ -f "$pc_dir/opus.pc" ]] || \
          ci_die "ToxAV needs the vcpkg opus port. Run: vcpkg install opus:$vcpkg_triplet libvpx:$vcpkg_triplet (or pass --no-toxav for a stub build)"
        [[ -f "$pc_dir/vpx.pc" ]] || \
          ci_die "ToxAV needs the vcpkg libvpx port. Run: vcpkg install libvpx:$vcpkg_triplet (or pass --no-toxav for a stub build)"
      fi

      local -a generator_args=()
      if [[ -n "${TIM2TOX_CMAKE_GENERATOR:-}" ]]; then
        generator_args=(-G "$TIM2TOX_CMAKE_GENERATOR")
      elif command -v ninja >/dev/null 2>&1; then
        generator_args=(-G "Ninja")
      elif [[ -d "/c/Program Files/Microsoft Visual Studio/18" ]]; then
        generator_args=(-G "Visual Studio 18" -A "$vs_arch")
      else
        generator_args=(-G "Visual Studio 17 2022" -A "$vs_arch")
      fi

      if [[ -n "${VCPKG_ROOT:-}" ]]; then
        local vcpkg_root_win toolchain_file
        vcpkg_root_win="$(ci_windows_path "$VCPKG_ROOT")"
        toolchain_file="${vcpkg_root_win}/scripts/buildsystems/vcpkg.cmake"
        # Ensure tools invoked by CMake/MSBuild are discoverable.
        # 1) pkg-config: used by FindPkgConfig during configure.
        export PATH="$VCPKG_ROOT/installed/$vcpkg_triplet/tools/pkgconf:$PATH"
        # 1b) .pc search path: pkgconf.exe is a native tool, so hand it a
        # Windows-style path. Without this, c-toxcore's pkg_search_module
        # cannot resolve opus.pc/vpx.pc (ToxAV deps) from vcpkg.
        local vcpkg_pc_dir_win
        vcpkg_pc_dir_win="$(ci_windows_path "$VCPKG_ROOT/installed/$vcpkg_triplet/lib/pkgconfig")"
        export PKG_CONFIG_PATH="$vcpkg_pc_dir_win"
        export PKG_CONFIG_LIBDIR="$vcpkg_pc_dir_win"
        # 2) powershell.exe: used by vcpkg's applocal.ps1 post-build step.
        # Git Bash (MSYS) typically exposes it under /c/WINDOWS/...
        export PATH="/c/WINDOWS/System32/WindowsPowerShell/v1.0:$PATH"
        # CMAKE_BUILD_TYPE is REQUIRED for single-config generators (Ninja): the
        # `cmake --build --config Release` below is a no-op for them, so without
        # this the dll links the DEBUG CRT (MSVCP140D.dll / ucrtbased.dll) +
        # pthreadVC3d.dll and fails to load at runtime with error 126. It is
        # harmless for the multi-config VS generator (which honors --config).
        # VCPKG_TARGET_TRIPLET must be EXPLICIT: with Ninja the vcpkg
        # toolchain guesses the target triplet from the host environment,
        # which on the windows-11-arm runners resolved to x64-windows while
        # the installed ports (and the pkg-config paths above) are
        # arm64-windows — the link step then got an x64 LIBPATH and failed
        # with LNK1181: cannot open input file 'opus.lib'.
        VCPKG_ROOT="$vcpkg_root_win" cmake -S "$source_dir_win" -B "$build_dir_win" \
          "${generator_args[@]}" \
          -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
          -DVCPKG_TARGET_TRIPLET="$vcpkg_triplet" \
          -DCMAKE_BUILD_TYPE=Release \
          "${configure_args[@]}"
      else
        cmake -S "$source_dir_win" -B "$build_dir_win" "${generator_args[@]}" \
          -DCMAKE_BUILD_TYPE=Release "${configure_args[@]}"
      fi
      ;;
    *)
      ci_die "Unsupported desktop target: $target"
      ;;
  esac

  ci_log "Building tim2tox_ffi for $target"
  cmake --build "$build_dir" --config Release --target tim2tox_ffi --parallel "$(ci_cpu_count)"

  built_lib="$(find "$build_dir" -type f -name "$lib_pattern" | head -n 1 || true)"
  [[ -n "$built_lib" ]] || ci_die "Failed to locate $lib_pattern under $build_dir"
  cp "$built_lib" "$OUTPUT_DIR/"
  ci_log "Captured native library: $built_lib"

  if [[ "$ENABLE_IRC" -eq 1 ]]; then
    ci_log "Building irc_client for $target"
    cmake --build "$build_dir" --config Release --target irc_client --parallel "$(ci_cpu_count)"
    local irc_pattern="libirc_client.so"
    case "$target" in
      windows) irc_pattern="libirc_client.dll" ;;
      macos)   irc_pattern="libirc_client.dylib" ;;
    esac
    local irc_lib
    irc_lib="$(find "$build_dir" -type f -name "$irc_pattern" | head -n 1 || true)"
    [[ -n "$irc_lib" ]] || ci_die "--with-irc requested but $irc_pattern was not produced under $build_dir"
    cp "$irc_lib" "$OUTPUT_DIR/"
    ci_log "Captured IRC client library: $irc_lib"
    if [[ "$target" == "windows" && -n "${VCPKG_ROOT:-}" ]]; then
      # libirc_client.dll links vcpkg OpenSSL dynamically; capture its DLLs so
      # launchers can stage them next to the app (missing dep = load error 126).
      # Search the RELEASE bin dir first — a whole-tree search would also match
      # debug/bin's DLLs, and staging a debug CRT-linked OpenSSL breaks loading.
      local ssl_pattern
      for ssl_pattern in "libssl-3*.dll" "libcrypto-3*.dll"; do
        ci_copy_matching_file "$VCPKG_ROOT/installed/$vcpkg_triplet/bin" "$ssl_pattern" "$OUTPUT_DIR" >/dev/null || \
          ci_copy_matching_file "$VCPKG_ROOT/installed/$vcpkg_triplet" "$ssl_pattern" "$OUTPUT_DIR" >/dev/null || \
          ci_warn "$ssl_pattern not found under $VCPKG_ROOT/installed/$vcpkg_triplet"
      done
    fi
    if [[ "$target" == "linux" ]]; then
      # Capture the system OpenSSL runtime next to the .so (same treatment as
      # libsodium) so the artifact set is self-contained on user machines.
      local dep_name dep_path
      for dep_name in libssl libcrypto; do
        dep_path="$(ldd "$irc_lib" | awk -v n="$dep_name" '$0 ~ n {print $3; exit}' || true)"
        if [[ -n "$dep_path" && -e "$dep_path" ]]; then
          capture_linux_shared_library "$dep_path"
          ci_log "Captured IRC dependency: $dep_path"
        fi
      done
    fi
  fi

  if [[ "$target" == "windows" && -n "${VCPKG_ROOT:-}" ]]; then
    ci_copy_matching_file "$VCPKG_ROOT/installed/$vcpkg_triplet" "libsodium.dll" "$OUTPUT_DIR" >/dev/null || \
      ci_warn "libsodium.dll not found under $VCPKG_ROOT/installed/$vcpkg_triplet"
    # c-toxcore links vcpkg pthreads on Windows, so tim2tox_ffi.dll imports the
    # release pthreadVC3.dll. Capture it next to libsodium.dll so the runner
    # bundle is self-contained (otherwise the FFI load fails with error 126).
    # The pattern excludes the debug pthreadVC3d.dll by name.
    ci_copy_matching_file "$VCPKG_ROOT/installed/$vcpkg_triplet" "pthreadVC3.dll" "$OUTPUT_DIR" >/dev/null || \
      ci_warn "pthreadVC3.dll not found under $VCPKG_ROOT/installed/$vcpkg_triplet"
    if [[ "$ENABLE_TOXAV" -eq 1 ]]; then
      # ToxAV runtime deps from vcpkg. A dep may be linked statically into
      # tim2tox_ffi.dll (the vcpkg libvpx port builds static even on dynamic
      # triplets) — then there is no runtime DLL and none is needed. Decide
      # from the built dll's IMPORT table (names are ASCII in the PE import
      # directory): import present + DLL missing = broken artifact (would
      # fail to load with error 126) → hard-fail; no import = statically
      # linked → nothing to capture.
      local built_dll="$OUTPUT_DIR/$(basename "$built_lib")"
      local dep_dll
      for dep_dll in "opus.dll" "vpx.dll libvpx.dll"; do
        local found_dep=""
        local candidate
        for candidate in $dep_dll; do
          if ci_copy_matching_file "$VCPKG_ROOT/installed/$vcpkg_triplet" "$candidate" "$OUTPUT_DIR" >/dev/null; then
            found_dep="$candidate"
            break
          fi
        done
        if [[ -n "$found_dep" ]]; then
          ci_log "Captured Windows ToxAV dependency: $found_dep"
          continue
        fi
        local imports_it=""
        for candidate in $dep_dll; do
          if grep -aFqi "$candidate" "$built_dll"; then
            imports_it="$candidate"
            break
          fi
        done
        if [[ -n "$imports_it" ]]; then
          ci_die "tim2tox_ffi.dll imports $imports_it but it was not found under $VCPKG_ROOT/installed/$vcpkg_triplet — the artifact would fail to load (error 126)"
        fi
        ci_log "ToxAV dependency ${dep_dll%% *} is statically linked — no runtime DLL to capture"
      done
    fi
  fi

  if [[ "$target" == "linux" ]]; then
    local dep_name dep_path
    for dep_name in libsodium libopus libvpx; do
      if [[ "$dep_name" != "libsodium" && "$ENABLE_TOXAV" -ne 1 ]]; then
        continue
      fi
      dep_path="$(ldd "$built_lib" | awk -v n="$dep_name" '$0 ~ n {print $3; exit}' || true)"
      if [[ -n "$dep_path" && -e "$dep_path" ]]; then
        capture_linux_shared_library "$dep_path"
        ci_log "Captured Linux dependency: $dep_path"
      elif [[ "$dep_name" != "libsodium" ]]; then
        # Uncaptured codec .so means calling breaks at load time on user
        # machines without the -dev packages — hard-fail.
        ci_die "Could not resolve ToxAV runtime dep $dep_name from $built_lib"
      else
        ci_warn "Could not resolve $dep_name dependency from $built_lib"
      fi
    done
  fi

  if [[ "$target" == "macos" ]]; then
    local dep_pattern dep_path
    for dep_pattern in 'libsodium.*dylib' 'libopus.*dylib' 'libvpx.*dylib'; do
      if [[ "$dep_pattern" != 'libsodium.*dylib' && "$ENABLE_TOXAV" -ne 1 ]]; then
        continue
      fi
      dep_path="$(otool -L "$built_lib" | awk -v p="$dep_pattern" '$1 ~ p {print $1; exit}' || true)"
      if [[ -n "$dep_path" && -f "$dep_path" ]]; then
        cp "$dep_path" "$OUTPUT_DIR/"
        ci_log "Captured macOS dependency: $dep_path"
      elif [[ "$dep_pattern" != 'libsodium.*dylib' ]]; then
        # Uncaptured codec dylib means calling breaks at load time on user
        # machines without Homebrew opus/libvpx — hard-fail.
        ci_die "Could not resolve ToxAV runtime dep $dep_pattern from $built_lib"
      else
        ci_warn "Could not resolve $dep_pattern dependency from $built_lib"
      fi
    done
  fi

  assert_toxav_artifact "$OUTPUT_DIR/$(basename "$built_lib")" nm "$target"
}

sync_ios_ffi_artifacts() {
  local copied="false"

  if [[ -n "${TIM2TOX_IOS_FRAMEWORK_PATH:-}" ]]; then
    [[ -d "${TIM2TOX_IOS_FRAMEWORK_PATH}" ]] || ci_die "TIM2TOX_IOS_FRAMEWORK_PATH does not exist: ${TIM2TOX_IOS_FRAMEWORK_PATH}"
    cp -R "${TIM2TOX_IOS_FRAMEWORK_PATH}" "$OUTPUT_DIR/"
    copied="true"
    ci_log "Captured iOS framework from ${TIM2TOX_IOS_FRAMEWORK_PATH}"
  fi

  if [[ -n "${TIM2TOX_IOS_DYLIB_PATH:-}" ]]; then
    [[ -f "${TIM2TOX_IOS_DYLIB_PATH}" ]] || ci_die "TIM2TOX_IOS_DYLIB_PATH does not exist: ${TIM2TOX_IOS_DYLIB_PATH}"
    cp "${TIM2TOX_IOS_DYLIB_PATH}" "$OUTPUT_DIR/"
    copied="true"
    ci_log "Captured iOS dylib from ${TIM2TOX_IOS_DYLIB_PATH}"
  fi

  if [[ "$copied" != "true" ]]; then
    build_ios_ffi_dylib
  else
    while IFS= read -r synced_lib; do
      assert_toxav_artifact "$synced_lib" nm "ios-synced"
    done < <(find "$OUTPUT_DIR" -type f \( -name 'tim2tox_ffi' -o -name 'libtim2tox_ffi.dylib' \))
  fi
}

case "$TARGET" in
  linux|windows|macos)
    build_desktop_target "$TARGET"
    ;;
  android)
    build_android_ffi_libs
    ;;
  ios)
    sync_ios_ffi_artifacts
    ;;
  *)
    ci_die "Unsupported target: $TARGET"
    ;;
esac

ci_log "Done preparing Tim2Tox artifacts for $TARGET ($MODE)"
