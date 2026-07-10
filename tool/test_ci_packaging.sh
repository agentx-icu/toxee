#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
ANDROID_JNI_DIR="$ROOT/android/app/src/main/jniLibs"

cleanup() {
  rm -rf "$TMP_ROOT"
  rm -rf "$ROOT/build/native-artifacts"
  rm -rf "$ROOT/dist/linux" "$ROOT/dist/ios"
  rm -rf "$ANDROID_JNI_DIR"
}
trap cleanup EXIT

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

assert_file_exists() {
  local path="$1"
  [[ -e "$path" ]] || fail "Expected file to exist: $path"
}

assert_file_missing() {
  local path="$1"
  [[ ! -e "$path" ]] || fail "Expected file to be absent: $path"
}

test_android_syncs_jni_libs_into_app_tree() {
  echo "[test] android syncs JNI libs into app tree"
  local src_dir="$TMP_ROOT/android-libs"
  mkdir -p "$src_dir/arm64-v8a"
  # The fake must carry the ToxAV marker export name — the sync path asserts
  # (via nm, falling back to binary grep) that synced artifacts are not
  # calling-stub builds.
  printf 'fake-so tim2tox_ffi_av_backend_toxav' > "$src_dir/arm64-v8a/libtim2tox_ffi.so"

  TIM2TOX_ANDROID_LIB_DIR="$src_dir" \
    bash "$ROOT/tool/ci/build_tim2tox.sh" --target android --mode release

  assert_file_exists "$ROOT/build/native-artifacts/android/jniLibs/arm64-v8a/libtim2tox_ffi.so"
  assert_file_exists "$ANDROID_JNI_DIR/arm64-v8a/libtim2tox_ffi.so"
}

test_android_sync_rejects_stub_libraries() {
  echo "[test] android sync rejects calling-stub libraries"
  local src_dir="$TMP_ROOT/android-libs-stub"
  mkdir -p "$src_dir/arm64-v8a"
  printf 'fake-so-without-marker' > "$src_dir/arm64-v8a/libtim2tox_ffi.so"

  if TIM2TOX_ANDROID_LIB_DIR="$src_dir" \
    bash "$ROOT/tool/ci/build_tim2tox.sh" --target android --mode release >/dev/null 2>&1; then
    fail "Expected ToxAV assertion to reject a marker-less (stub) library"
  fi

  # And the explicit stub opt-out must accept the same library.
  TIM2TOX_ANDROID_LIB_DIR="$src_dir" \
    bash "$ROOT/tool/ci/build_tim2tox.sh" --target android --mode release --no-toxav
  assert_file_exists "$ANDROID_JNI_DIR/arm64-v8a/libtim2tox_ffi.so"
}

test_linux_packaging_supports_deb_and_rpm_installers() {
  echo "[test] linux packaging supports deb and rpm installers"
  rg -n 'toxee-\\$release_version-Linux-\\$PACKAGE_ARCH\\.deb|toxee-\\$release_version-Linux-\\$PACKAGE_ARCH\\.rpm|Bundled Linux runtime dependency|Normalized Linux FFI rpath' \
    "$ROOT/tool/ci/package_artifacts.sh" >/dev/null || \
    fail "Linux packaging script does not appear to produce DEB/RPM installers with bundled runtime notes"
  rg -n 'CPACK_GENERATOR \"DEB;RPM\"|TOXEE_DEB_ARCH|TOXEE_RPM_ARCH|usr/share/applications|usr/share/icons' \
    "$ROOT/tool/ci/linux-installer/CMakeLists.txt" >/dev/null || \
    fail "Linux installer CPack config is missing"
}

test_ios_unsigned_build_is_packaged_as_validation_ipa() {
  echo "[test] unsigned iOS build is packaged as validation ipa"
  rm -rf "$ROOT/dist/ios" "$ROOT/build/ios/iphoneos"
  mkdir -p "$ROOT/build/ios/iphoneos/Runner.app/Frameworks"

  bash "$ROOT/tool/ci/package_artifacts.sh" --target ios --mode release

  assert_file_missing "$ROOT/dist/ios/toxee-ios-release.zip"
  assert_file_exists "$ROOT/dist/ios/toxee-ios-release.ipa"
  assert_file_exists "$ROOT/dist/ios/NOTES.txt"
}

test_ios_signed_build_is_packaged_as_ipa() {
  echo "[test] signed iOS build is packaged as ipa"
  rm -rf "$ROOT/dist/ios" "$ROOT/build/ios/iphoneos"
  local fake_bin="$TMP_ROOT/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/codesign" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fake_bin/codesign"
  mkdir -p "$ROOT/build/ios/iphoneos/Runner.app/Frameworks"
  printf 'signed' > "$ROOT/build/ios/iphoneos/Runner.app/embedded.mobileprovision"
  mkdir -p "$ROOT/build/native-artifacts/ios/tim2tox_ffi.framework"
  # Must carry the ToxAV marker export name — packaging refuses stub builds.
  printf 'ffi-framework tim2tox_ffi_av_backend_toxav' > "$ROOT/build/native-artifacts/ios/tim2tox_ffi.framework/tim2tox_ffi"

  PATH="$fake_bin:$PATH" IOS_SIGNING_IDENTITY="Test Identity" \
    bash "$ROOT/tool/ci/package_artifacts.sh" --target ios --mode release

  assert_file_exists "$ROOT/dist/ios/toxee-ios-release.ipa"
  local zip_listing
  zip_listing="$(unzip -l "$ROOT/dist/ios/toxee-ios-release.ipa")"
  grep -q 'Payload/Runner.app/Frameworks/tim2tox_ffi.framework/tim2tox_ffi' <<<"$zip_listing" || \
    fail "Expected signed IPA to contain injected tim2tox_ffi framework"
}

test_workflow_does_not_use_secrets_in_if_conditions() {
  echo "[test] workflow avoids secrets in if conditions"
  if rg -n '^[[:space:]]*if:.*secrets\\.' "$ROOT/.github/workflows/build-packages.yml" >/dev/null; then
    fail "Workflow still uses secrets directly in if conditions"
  fi
}

test_analyze_workflow_tolerates_existing_warnings() {
  echo "[test] analyze workflow is non-fatal for existing warnings"
  rg -n 'flutter analyze lib tool --no-fatal-warnings --no-fatal-infos' "$ROOT/.github/workflows/analyze.yml" >/dev/null || \
    fail "Analyze workflow still treats warnings as fatal"
}

test_desktop_release_workflow_uses_multi_arch_installers() {
  echo "[test] desktop workflow uses multi-arch installer packaging"
  rg -n 'ubuntu-24\\.04-arm|macos-15-intel|macos-15|windows-11-arm|windows-2025|package_arch: aarch64|package_arch: arm64|package_arch: AMD64|package_arch: ARM64' \
    "$ROOT/.github/workflows/build-packages.yml" >/dev/null || \
    fail "Desktop release workflow does not appear to define the expected multi-arch matrix"
  rg -n 'cpack -C Release -G WIX|\\.msi|\\.deb|\\.rpm|pkgbuild' \
    "$ROOT/.github/workflows/build-packages.yml" "$ROOT/tool/ci/package_artifacts.sh" >/dev/null || \
    fail "Desktop release flow does not appear to produce MSI/DEB/RPM/PKG installers"
  rg -n 'CPACK_GENERATOR "WIX"|CPACK_WIX_UPGRADE_GUID|install\(' \
    "$ROOT/tool/ci/windows-installer/CMakeLists.txt" >/dev/null || \
    fail "Dedicated Windows MSI packaging config is missing"
  rg -n 'CPACK_GENERATOR "DEB;RPM"|TOXEE_DEB_ARCH|TOXEE_RPM_ARCH|usr/share/applications|usr/share/icons' \
    "$ROOT/tool/ci/linux-installer/CMakeLists.txt" >/dev/null || \
    fail "Dedicated Linux installer packaging config is missing"
}

test_release_publish_filters_non_installable_mobile_assets() {
  echo "[test] release publish filters non-installable mobile assets"
  local artifacts_dir="$TMP_ROOT/release-artifacts"
  mkdir -p "$artifacts_dir/toxee-android-release" "$artifacts_dir/toxee-ios-release" "$artifacts_dir/toxee-windows-release"

  printf 'apk' > "$artifacts_dir/toxee-android-release/toxee-0.1.7-Android-arm64.apk"
  printf 'aab' > "$artifacts_dir/toxee-android-release/toxee-0.1.7-Android-arm64.aab"
  cat > "$artifacts_dir/toxee-android-release/NOTES.txt" <<'EOF'
No Android Tim2Tox JNI libraries were staged. APK/AAB were built, but runtime native loading still needs libtim2tox_ffi.so packaging.
EOF

  printf 'ipa' > "$artifacts_dir/toxee-ios-release/toxee-ios-release.ipa"
  cat > "$artifacts_dir/toxee-ios-release/NOTES.txt" <<'EOF'
Packaged unsigned iOS app as IPA.
Unsigned iOS IPA was packaged without an injected Tim2Tox FFI artifact.
EOF

  printf 'msi' > "$artifacts_dir/toxee-windows-release/toxee-windows-x64-release.msi"
  cat > "$artifacts_dir/toxee-windows-release/NOTES.txt" <<'EOF'
Bundled tim2tox_ffi.dll into Windows package.
Bundled libsodium.dll into Windows package.
EOF

  PATH="/usr/bin:/bin" \
    RELEASE_DRY_RUN=1 RELEASE_TAG=vtest RELEASE_ARTIFACTS_DIR="$artifacts_dir" \
    bash "$ROOT/tool/ci/publish_release.sh"

  assert_file_exists "$ROOT/dist/github-release/toxee-windows-x64-release.msi"
  assert_file_missing "$ROOT/dist/github-release/toxee-0.1.7-Android-arm64.apk"
  assert_file_missing "$ROOT/dist/github-release/toxee-0.1.7-Android-arm64.aab"
  assert_file_missing "$ROOT/dist/github-release/toxee-ios-release.ipa"
}

test_release_publish_keeps_expected_installer_types() {
  echo "[test] release publish keeps expected installer types"
  local artifacts_dir="$TMP_ROOT/release-installers"
  mkdir -p \
    "$artifacts_dir/toxee-linux-x86_64-release" \
    "$artifacts_dir/toxee-linux-aarch64-release" \
    "$artifacts_dir/toxee-macos-x86_64-release" \
    "$artifacts_dir/toxee-macos-arm64-release" \
    "$artifacts_dir/toxee-windows-AMD64-release" \
    "$artifacts_dir/toxee-windows-ARM64-release" \
    "$artifacts_dir/toxee-android-release" \
    "$artifacts_dir/toxee-ios-release"

  printf 'linux-deb' > "$artifacts_dir/toxee-linux-x86_64-release/toxee-0.1.7-Linux-x86_64.deb"
  printf 'linux-rpm' > "$artifacts_dir/toxee-linux-x86_64-release/toxee-0.1.7-Linux-x86_64.rpm"
  printf 'appimage' > "$artifacts_dir/toxee-linux-x86_64-release/toxee-linux-x64-release.AppImage"
  cat > "$artifacts_dir/toxee-linux-x86_64-release/NOTES.txt" <<'EOF'
Bundled libtim2tox_ffi.so into Linux bundle.
EOF

  printf 'linux-deb-arm' > "$artifacts_dir/toxee-linux-aarch64-release/toxee-0.1.7-Linux-aarch64.deb"
  printf 'linux-rpm-arm' > "$artifacts_dir/toxee-linux-aarch64-release/toxee-0.1.7-Linux-aarch64.rpm"
  cat > "$artifacts_dir/toxee-linux-aarch64-release/NOTES.txt" <<'EOF'
Bundled libtim2tox_ffi.so into Linux bundle.
EOF

  printf 'mac-pkg' > "$artifacts_dir/toxee-macos-x86_64-release/toxee-0.1.7-Darwin-x86_64.pkg"
  printf 'dmg' > "$artifacts_dir/toxee-macos-x86_64-release/toxee-macos-release.dmg"
  cat > "$artifacts_dir/toxee-macos-x86_64-release/NOTES.txt" <<'EOF'
Bundled libtim2tox_ffi.dylib into macOS app.
EOF

  printf 'mac-pkg-arm' > "$artifacts_dir/toxee-macos-arm64-release/toxee-0.1.7-Darwin-arm64.pkg"
  printf 'mac-zip' > "$artifacts_dir/toxee-macos-arm64-release/toxee-macos-release.zip"
  cat > "$artifacts_dir/toxee-macos-arm64-release/NOTES.txt" <<'EOF'
Bundled libtim2tox_ffi.dylib into macOS app.
EOF

  printf 'msi' > "$artifacts_dir/toxee-windows-AMD64-release/toxee-0.1.7-Windows-AMD64.msi"
  printf 'win-zip' > "$artifacts_dir/toxee-windows-AMD64-release/toxee-windows-x64-release.zip"
  cat > "$artifacts_dir/toxee-windows-AMD64-release/NOTES.txt" <<'EOF'
Bundled tim2tox_ffi.dll into Windows package.
EOF

  printf 'msi-arm' > "$artifacts_dir/toxee-windows-ARM64-release/toxee-0.1.7-Windows-ARM64.msi"
  cat > "$artifacts_dir/toxee-windows-ARM64-release/NOTES.txt" <<'EOF'
Bundled tim2tox_ffi.dll into Windows package.
EOF

  printf 'apk' > "$artifacts_dir/toxee-android-release/toxee-0.1.7-Android-arm64.apk"
  printf 'aab' > "$artifacts_dir/toxee-android-release/toxee-0.1.7-Android-arm64.aab"
  cat > "$artifacts_dir/toxee-android-release/NOTES.txt" <<'EOF'
Android build used repository-provided Tim2Tox JNI libraries.
EOF

  printf 'ipa' > "$artifacts_dir/toxee-ios-release/toxee-ios-release.ipa"
  cat > "$artifacts_dir/toxee-ios-release/NOTES.txt" <<'EOF'
Packaged signed iOS app as IPA.
Injected Tim2Tox FFI artifact into signed iOS app before IPA packaging.
EOF

  PATH="/usr/bin:/bin" \
    RELEASE_DRY_RUN=1 RELEASE_TAG=vtest RELEASE_ARTIFACTS_DIR="$artifacts_dir" \
    bash "$ROOT/tool/ci/publish_release.sh"

  assert_file_exists "$ROOT/dist/github-release/toxee-0.1.7-Linux-x86_64.deb"
  assert_file_exists "$ROOT/dist/github-release/toxee-0.1.7-Linux-x86_64.rpm"
  assert_file_exists "$ROOT/dist/github-release/toxee-0.1.7-Linux-aarch64.deb"
  assert_file_exists "$ROOT/dist/github-release/toxee-0.1.7-Linux-aarch64.rpm"
  assert_file_exists "$ROOT/dist/github-release/toxee-0.1.7-Darwin-x86_64.pkg"
  assert_file_exists "$ROOT/dist/github-release/toxee-0.1.7-Darwin-arm64.pkg"
  assert_file_exists "$ROOT/dist/github-release/toxee-0.1.7-Windows-AMD64.msi"
  assert_file_exists "$ROOT/dist/github-release/toxee-0.1.7-Windows-ARM64.msi"
  assert_file_exists "$ROOT/dist/github-release/toxee-0.1.7-Android-arm64.apk"
  assert_file_exists "$ROOT/dist/github-release/toxee-ios-release.ipa"
  assert_file_exists "$ROOT/dist/github-release/SHA256SUMS.txt"

  assert_file_missing "$ROOT/dist/github-release/toxee-linux-x64-release.AppImage"
  assert_file_missing "$ROOT/dist/github-release/toxee-macos-release.dmg"
  assert_file_missing "$ROOT/dist/github-release/toxee-macos-release.zip"
  assert_file_missing "$ROOT/dist/github-release/toxee-windows-x64-release.zip"
  assert_file_missing "$ROOT/dist/github-release/toxee-0.1.7-Android-arm64.aab"
  assert_file_missing "$ROOT/dist/github-release/BUILD-NOTES.txt"
}

test_mobile_build_script_supports_android_and_ios_ci_builds() {
  echo "[test] mobile build script supports Android and iOS CI builds"
  rg -n 'build_android_ffi_for_abi|ANDROID_ABIS=|android\\.toolchain\\.cmake|build_ios_ffi_dylib|TIM2TOX_DEP_PREFIX|CMAKE_OSX_SYSROOT' \
    "$ROOT/tool/ci/build_tim2tox.sh" "$ROOT/third_party/tim2tox/CMakeLists.txt" \
    "$ROOT/third_party/tim2tox/source/CMakeLists.txt" "$ROOT/third_party/tim2tox/ffi/CMakeLists.txt" >/dev/null || \
    fail "Mobile CI native build support is missing from tim2tox build scripts/CMake config"
}

test_signed_ios_packaging_resigns_injected_native_binary() {
  echo "[test] signed iOS packaging re-signs injected native binary"
  rg -n 'codesign --force --sign .*IOS_SIGNING_IDENTITY|codesign -d --entitlements|IOS_SIGNING_IDENTITY' \
    "$ROOT/tool/ci/package_artifacts.sh" >/dev/null || \
    fail "Signed iOS packaging does not appear to re-sign injected native binaries"
}

test_android_syncs_jni_libs_into_app_tree
test_android_sync_rejects_stub_libraries
test_linux_packaging_supports_deb_and_rpm_installers
test_ios_unsigned_build_is_packaged_as_validation_ipa
test_ios_signed_build_is_packaged_as_ipa
test_workflow_does_not_use_secrets_in_if_conditions
test_analyze_workflow_tolerates_existing_warnings
test_desktop_release_workflow_uses_multi_arch_installers
test_release_publish_filters_non_installable_mobile_assets
test_release_publish_keeps_expected_installer_types
test_mobile_build_script_supports_android_and_ios_ci_builds
test_signed_ios_packaging_resigns_injected_native_binary

echo "[PASS] all packaging regression tests passed"
