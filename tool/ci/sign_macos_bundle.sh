#!/usr/bin/env bash
# Run after the final dylib copy/install_name_tool mutation, before pkgbuild.
set -euo pipefail
app_bundle="${1:?Usage: sign_macos_bundle.sh APP [IDENTITY]}"
signing_identity="${2:--}"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
sign_code() {
  if [[ "$signing_identity" == '-' ]]; then
    codesign --force --sign - "$1"
  else
    codesign --force --sign "$signing_identity" --options runtime --timestamp "$1"
  fi
}
# Sign individual native images first, then containing bundles from the inside
# out. This includes Flutter/plugin frameworks as well as newly copied dylibs.
while IFS= read -r -d '' native_image; do
  if file -b "$native_image" | grep -q 'Mach-O'; then
    sign_code "$native_image"
  fi
done < <(find "$app_bundle/Contents" -type f -print0)
while IFS= read -r -d '' nested_bundle; do
  sign_code "$nested_bundle"
done < <(find "$app_bundle/Contents" -depth -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' -o -name '*.appex' \) -print0)
if [[ "$signing_identity" == '-' ]]; then
  codesign --force --sign - --entitlements "$repo_root/macos/Runner/Release.entitlements" "$app_bundle"
else
  codesign --force --sign "$signing_identity" --options runtime --timestamp \
    --entitlements "$repo_root/macos/Runner/Release.entitlements" "$app_bundle"
fi
codesign --verify --deep --strict --verbose=2 "$app_bundle"
