#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tool/ci/common.sh
source "$SCRIPT_DIR/common.sh"

TARGET=""
MODE="release"
PACKAGE_ARCH="${TOXEE_PACKAGE_ARCH:-}"

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
    --help|-h)
      cat <<'EOF'
Usage: package_artifacts.sh --target <linux|windows|macos|android|ios> [--mode <debug|profile|release>]
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
DIST_DIR="$REPO_ROOT/dist/$TARGET"
NATIVE_DIR="$REPO_ROOT/build/native-artifacts/$TARGET"
MODE_DIR="$(ci_mode_dirname "$MODE")"

ci_reset_dir "$DIST_DIR"

resolve_release_version() {
  local release_version="${RELEASE_VERSION:-}"

  if [[ -z "$release_version" && "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
    release_version="${GITHUB_REF_NAME#v}"
  fi

  if [[ -z "$release_version" ]]; then
    release_version="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' "$REPO_ROOT/pubspec.yaml" | head -n 1)"
  fi

  [[ -n "$release_version" ]] || ci_die "Could not determine release version"
  printf '%s\n' "$release_version"
}

detect_linux_bundle_dir() {
  find "$REPO_ROOT/build/linux" -type d -path "*/$MODE/bundle" | head -n 1
}

detect_windows_runner_dir() {
  find "$REPO_ROOT/build/windows" -type d -path "*/runner/$MODE_DIR" | head -n 1
}

write_note() {
  local note_file="$DIST_DIR/NOTES.txt"
  printf '%s\n' "$1" >> "$note_file"
}

resign_ios_bundle_if_needed() {
  local app_bundle="$1"
  local frameworks_dir="$2"
  local identity="${IOS_SIGNING_IDENTITY:-}"
  local item

  [[ -n "$identity" ]] || ci_die "IOS_SIGNING_IDENTITY is required to re-sign injected iOS native artifacts"
  command -v codesign >/dev/null 2>&1 || ci_die "codesign is required for signed iOS packaging"

  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    codesign --force --sign "$identity" --timestamp=none "$item"
  done < <(find "$frameworks_dir" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) | sort)

  codesign \
    --force \
    --sign "$identity" \
    --timestamp=none \
    --preserve-metadata=identifier,entitlements \
    "$app_bundle"
  codesign --verify --deep --strict "$app_bundle"
}

package_linux() {
  local bundle_dir staged_dir installer_build_dir release_version deb_arch rpm_arch
  local bundled_sodium="false"

  [[ -n "$PACKAGE_ARCH" ]] || ci_die "TOXEE_PACKAGE_ARCH is required for Linux packaging"
  bundle_dir="$(detect_linux_bundle_dir)"
  staged_dir="$DIST_DIR/toxee-linux-$PACKAGE_ARCH"
  installer_build_dir="$REPO_ROOT/build/linux/installer-$PACKAGE_ARCH"
  release_version="$(resolve_release_version)"

  case "$PACKAGE_ARCH" in
    x86_64)
      deb_arch="amd64"
      rpm_arch="x86_64"
      ;;
    aarch64|arm64)
      PACKAGE_ARCH="aarch64"
      deb_arch="arm64"
      rpm_arch="aarch64"
      ;;
    *)
      ci_die "Unsupported Linux package architecture: $PACKAGE_ARCH"
      ;;
  esac

  [[ -d "$bundle_dir" ]] || ci_die "Linux bundle not found: $bundle_dir"

  rm -rf "$staged_dir"
  mkdir -p "$staged_dir"
  cp -R "$bundle_dir"/. "$staged_dir/"
  mkdir -p "$staged_dir/lib"

  if [[ -f "$NATIVE_DIR/libtim2tox_ffi.so" ]]; then
    cp "$NATIVE_DIR/libtim2tox_ffi.so" "$staged_dir/lib/"
    write_note "Bundled libtim2tox_ffi.so into Linux bundle."
  else
    write_note "libtim2tox_ffi.so was not found. The Linux bundle was packaged without the Tim2Tox native library."
  fi

  while IFS= read -r sodium_file; do
    [[ -n "$sodium_file" ]] || continue
    cp -a "$sodium_file" "$staged_dir/lib/"
    bundled_sodium="true"
  done < <(find "$NATIVE_DIR" -maxdepth 1 \( -type f -o -type l \) -name 'libsodium*.so*' | sort)

  if [[ "$bundled_sodium" == "true" ]]; then
    write_note "Bundled Linux libsodium runtime dependency."
  else
    write_note "Linux libsodium runtime dependency was not captured; target host may need libsodium preinstalled."
  fi

  if command -v patchelf >/dev/null 2>&1 && command -v file >/dev/null 2>&1; then
    if [[ -f "$staged_dir/lib/libtim2tox_ffi.so" ]] && file "$staged_dir/lib/libtim2tox_ffi.so" | grep -qi 'ELF'; then
      patchelf --set-rpath '$ORIGIN' "$staged_dir/lib/libtim2tox_ffi.so"
      write_note "Normalized Linux FFI rpath to \$ORIGIN."
    fi
  fi

  rm -rf "$installer_build_dir"
  if command -v cpack >/dev/null 2>&1; then
    cmake -S "$REPO_ROOT/tool/ci/linux-installer" -B "$installer_build_dir" \
      -DTOXEE_INSTALLER_SOURCE_DIR="$staged_dir" \
      -DTOXEE_RELEASE_VERSION="$release_version" \
      -DTOXEE_PACKAGE_ARCH="$PACKAGE_ARCH" \
      -DTOXEE_DEB_ARCH="$deb_arch" \
      -DTOXEE_RPM_ARCH="$rpm_arch" >/dev/null
    (
      cd "$installer_build_dir"
      cpack -G "DEB;RPM"
    )

    local deb_output rpm_output deb_path rpm_path
    deb_output="$(find "$installer_build_dir" -maxdepth 1 -type f -name '*.deb' | head -n 1 || true)"
    rpm_output="$(find "$installer_build_dir" -maxdepth 1 -type f -name '*.rpm' | head -n 1 || true)"
    deb_path="$DIST_DIR/toxee-$release_version-Linux-$PACKAGE_ARCH.deb"
    rpm_path="$DIST_DIR/toxee-$release_version-Linux-$PACKAGE_ARCH.rpm"

    [[ -n "$deb_output" && -f "$deb_output" ]] || ci_die "Linux DEB package was not produced"
    [[ -n "$rpm_output" && -f "$rpm_output" ]] || ci_die "Linux RPM package was not produced"

    cp "$deb_output" "$deb_path"
    cp "$rpm_output" "$rpm_path"
    ci_log "Created Linux DEB: $deb_path"
    ci_log "Created Linux RPM: $rpm_path"
  else
    ci_die "cpack is required for Linux installer packaging"
  fi

  rm -rf "$staged_dir"
}

package_windows() {
  local runner_dir staged_dir
  local installer_build_dir="$REPO_ROOT/build/windows/installer"
  local installer_source_dir
  local package_arch="$PACKAGE_ARCH"

  [[ -n "$package_arch" ]] || ci_die "TOXEE_PACKAGE_ARCH is required for Windows packaging"
  runner_dir="$(detect_windows_runner_dir)"
  staged_dir="$DIST_DIR/toxee-windows-$package_arch"
  installer_source_dir="$staged_dir"
  [[ -d "$runner_dir" ]] || ci_die "Windows runner output not found: $runner_dir"

  rm -rf "$staged_dir"
  mkdir -p "$staged_dir"
  cp -R "$runner_dir"/. "$staged_dir/"

  if [[ -f "$NATIVE_DIR/tim2tox_ffi.dll" ]]; then
    cp "$NATIVE_DIR/tim2tox_ffi.dll" "$staged_dir/"
    write_note "Bundled tim2tox_ffi.dll into Windows package."
  else
    write_note "tim2tox_ffi.dll was not found. The Windows package was created without the Tim2Tox native library."
  fi

  if [[ -f "$NATIVE_DIR/libsodium.dll" ]]; then
    cp "$NATIVE_DIR/libsodium.dll" "$staged_dir/"
    write_note "Bundled libsodium.dll into Windows package."
  fi

  # --- MSI installer via CPack/WiX ---
  local msi_path release_version
  release_version="$(resolve_release_version)"
  msi_path="$DIST_DIR/toxee-$release_version-Windows-$package_arch.msi"

  if command -v cpack >/dev/null 2>&1; then
    rm -rf "$installer_build_dir"
    if (
      cmake -S "$REPO_ROOT/tool/ci/windows-installer" -B "$installer_build_dir" \
        -DTOXEE_INSTALLER_SOURCE_DIR="$(ci_windows_path "$installer_source_dir")" \
        -DTOXEE_PACKAGE_ARCH="$package_arch" \
        -DTOXEE_RELEASE_VERSION="$release_version" >/dev/null && \
      cd "$installer_build_dir" && \
      cpack -C Release -G WIX \
        --verbose
    ); then
      local msi_output
      msi_output="$(find "$installer_build_dir" -maxdepth 1 -type f -name '*.msi' | head -n 1 || true)"
      if [[ -n "$msi_output" && -f "$msi_output" ]]; then
        cp "$msi_output" "$msi_path"
        ci_log "Created Windows MSI: $msi_path"
      else
        ci_warn "CPack WIX completed but MSI output not found"
      fi
    else
      ci_warn "CPack WIX failed; skipping MSI installer"
    fi
  else
    ci_warn "CPack config or cpack executable missing; skipping MSI installer"
  fi

  rm -rf "$staged_dir"
}

package_macos() {
  local app_bundle="$REPO_ROOT/build/macos/Build/Products/$MODE_DIR/Toxee.app"
  local macos_dir="$app_bundle/Contents/MacOS"
  local ffi_lib="$NATIVE_DIR/libtim2tox_ffi.dylib"
  local sodium_lib release_version pkg_path

  [[ -n "$PACKAGE_ARCH" ]] || ci_die "TOXEE_PACKAGE_ARCH is required for macOS packaging"
  if [[ ! -d "$app_bundle" ]]; then
    app_bundle="$(find "$REPO_ROOT/build/macos/Build/Products/$MODE_DIR" -maxdepth 1 -type d -name '*.app' | head -n 1 || true)"
  fi
  [[ -n "$app_bundle" && -d "$app_bundle" ]] || ci_die "macOS app bundle not found under build/macos/Build/Products/$MODE_DIR"

  mkdir -p "$macos_dir"

  if [[ -f "$ffi_lib" ]]; then
    cp "$ffi_lib" "$macos_dir/"
    write_note "Bundled libtim2tox_ffi.dylib into macOS app."

    sodium_lib="$(find "$NATIVE_DIR" -maxdepth 1 -type f -name 'libsodium*.dylib' | head -n 1 || true)"
    if [[ -n "$sodium_lib" ]]; then
      cp "$sodium_lib" "$macos_dir/"
      local old_path new_name
      old_path="$(otool -L "$ffi_lib" | awk '/libsodium.*dylib/ {print $1; exit}' || true)"
      new_name="$(basename "$sodium_lib")"
      if [[ -n "$old_path" ]]; then
        install_name_tool -change "$old_path" "@loader_path/$new_name" "$macos_dir/$(basename "$ffi_lib")"
      fi
      write_note "Bundled $(basename "$sodium_lib") into macOS app."
    fi
  else
    write_note "libtim2tox_ffi.dylib was not found. The macOS app was packaged without the Tim2Tox native library."
  fi

  release_version="$(resolve_release_version)"
  pkg_path="$DIST_DIR/toxee-$release_version-Darwin-$PACKAGE_ARCH.pkg"
  pkgbuild \
    --identifier "com.toxee.app" \
    --version "$release_version" \
    --install-location "/Applications" \
    --component "$app_bundle" \
    "$pkg_path"
  ci_log "Created macOS PKG: $pkg_path"
}

package_android() {
  local apk_path="$REPO_ROOT/build/app/outputs/flutter-apk/app-$MODE.apk"
  local aab_path="$REPO_ROOT/build/app/outputs/bundle/$MODE/app-$MODE.aab"
  local release_version package_arch output_apk_name output_aab_name

  release_version="$(resolve_release_version)"
  package_arch="${TOXEE_PACKAGE_ARCH:-arm64}"
  output_apk_name="toxee-${release_version}-Android-${package_arch}.apk"
  output_aab_name="toxee-${release_version}-Android-${package_arch}.aab"

  [[ -f "$apk_path" ]] || ci_die "Android APK not found: $apk_path"
  cp "$apk_path" "$DIST_DIR/$output_apk_name"
  ci_log "Captured Android APK: $DIST_DIR/$output_apk_name"

  if [[ -f "$aab_path" ]]; then
    cp "$aab_path" "$DIST_DIR/$output_aab_name"
    ci_log "Captured Android App Bundle: $DIST_DIR/$output_aab_name"
  else
    write_note "Android App Bundle was not produced."
  fi

  if [[ -d "$NATIVE_DIR/jniLibs" ]] && find "$NATIVE_DIR/jniLibs" -type f -name "libtim2tox_ffi.so" | grep -q .; then
    write_note "Android build used repository-provided Tim2Tox JNI libraries."
  else
    write_note "No Android Tim2Tox JNI libraries were staged. APK/AAB were built, but runtime native loading still needs libtim2tox_ffi.so packaging."
  fi
}

package_ios() {
  local app_bundle="$REPO_ROOT/build/ios/iphoneos/Runner.app"
  local archive_path="$DIST_DIR/toxee-ios-$MODE.ipa"
  local frameworks_dir="$app_bundle/Frameworks"
  local framework_src="$NATIVE_DIR/tim2tox_ffi.framework"
  local dylib_src="$NATIVE_DIR/libtim2tox_ffi.dylib"
  local payload_dir="$DIST_DIR/Payload"
  local signed_marker="$app_bundle/embedded.mobileprovision"
  local injected="false"

  [[ -d "$app_bundle" ]] || ci_die "iOS app bundle not found: $app_bundle"

  mkdir -p "$frameworks_dir"
  if [[ -d "$framework_src" ]]; then
    rm -rf "$frameworks_dir/tim2tox_ffi.framework"
    cp -R "$framework_src" "$frameworks_dir/"
    injected="true"
  elif [[ -f "$dylib_src" ]]; then
    cp "$dylib_src" "$frameworks_dir/"
    injected="true"
  fi

  if [[ -f "$signed_marker" ]]; then
    if [[ "$injected" == "true" ]]; then
      resign_ios_bundle_if_needed "$app_bundle" "$frameworks_dir"
      write_note "Re-signed iOS app after injecting Tim2Tox native artifacts."
    fi
    mkdir -p "$payload_dir"
    cp -R "$app_bundle" "$payload_dir/"
    (cd "$DIST_DIR" && zip -qry "$(basename "$archive_path")" Payload)
    rm -rf "$payload_dir"
    ci_log "Created iOS IPA: $archive_path"
    write_note "Packaged signed iOS app as IPA."
    if [[ "$injected" == "true" ]]; then
      write_note "Injected Tim2Tox FFI artifact into signed iOS app before IPA packaging."
    else
      write_note "Signed iOS IPA was packaged without an injected Tim2Tox FFI artifact."
    fi
    return
  fi

  if [[ "${IOS_SIGNING_READY:-false}" == "true" ]]; then
    ci_die "iOS signing was configured, but the built app bundle is not signed (missing embedded.mobileprovision)."
  fi

  # Create unsigned IPA (Payload/Runner.app zip)
  mkdir -p "$payload_dir"
  cp -R "$app_bundle" "$payload_dir/"
  (cd "$DIST_DIR" && zip -qry "$(basename "$archive_path")" Payload)
  rm -rf "$payload_dir"
  ci_log "Created unsigned iOS IPA: $archive_path"
  write_note "Packaged unsigned iOS app as IPA."
  if [[ "$injected" == "true" ]]; then
    write_note "Injected Tim2Tox FFI artifact into unsigned iOS app before IPA packaging."
  else
    write_note "Unsigned iOS IPA was packaged without an injected Tim2Tox FFI artifact."
  fi
}

case "$TARGET" in
  linux) package_linux ;;
  windows) package_windows ;;
  macos) package_macos ;;
  android) package_android ;;
  ios) package_ios ;;
  *) ci_die "Unsupported target: $TARGET" ;;
esac
