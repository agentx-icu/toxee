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
# codesign treats a bundle's CFBundleExecutable path as the containing bundle.
# Signing that file early therefore validates still-unsigned sibling libraries.
# Defer those entry points to the bundle pass; sign only loose native code first.
nested_bundles=()
bundle_executables=()
while IFS= read -r -d '' nested_bundle; do
  nested_bundles+=("$nested_bundle")
done < <(find "$app_bundle/Contents" -depth -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' -o -name '*.appex' \) -print0)
for bundle in "${nested_bundles[@]:-}" "$app_bundle"; do
  [[ -n "$bundle" ]] || continue
  executable=""
  for plist in "$bundle/Contents/Info.plist" "$bundle/Resources/Info.plist" "$bundle/Info.plist"; do
    [[ -f "$plist" ]] || continue
    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null || true)"
    [[ -z "$executable" ]] || break
  done
  # Without this key codesign treats native files as loose code. Do not infer
  # an entry point from the directory name and leave that file unsigned.
  [[ -n "$executable" ]] || continue
  for candidate in "$bundle/Contents/MacOS/$executable" "$bundle/$executable"; do
    if [[ -f "$candidate" ]]; then
      bundle_executables+=("$candidate")
      break
    fi
  done
done
is_bundle_executable() {
  local executable
  for executable in "${bundle_executables[@]:-}"; do
    # -ef compares the target inode, including framework Versions/Current links.
    if [[ -n "$executable" && "$1" -ef "$executable" ]]; then return 0; fi
  done
  return 1
}
while IFS= read -r -d '' native_image; do
  if is_bundle_executable "$native_image"; then continue; fi
  if file -b "$native_image" | grep -q 'Mach-O'; then
    sign_code "$native_image"
  fi
done < <(find "$app_bundle/Contents" -type f -print0)
# Each entry point is signed with its bundle after all of its children.
for nested_bundle in "${nested_bundles[@]:-}"; do
  [[ -n "$nested_bundle" ]] || continue
  sign_code "$nested_bundle"
done
if [[ "$signing_identity" == '-' ]]; then
  codesign --force --sign - --entitlements "$repo_root/macos/Runner/Release.entitlements" "$app_bundle"
else
  codesign --force --sign "$signing_identity" --options runtime --timestamp \
    --entitlements "$repo_root/macos/Runner/Release.entitlements" "$app_bundle"
fi
codesign --verify --deep --strict --verbose=2 "$app_bundle"
