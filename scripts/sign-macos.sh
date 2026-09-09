#!/usr/bin/env bash
set -euo pipefail
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo 'Apple Silicon macOS is required.' >&2; exit 1; }
: "${SIGNING_IDENTITY:?Set the Developer ID identity in the private environment}"
: "${NOTARY_PROFILE:?Set the existing Keychain profile name}"
app=${1:?Pass an exported RetroLife.app path}
[[ -d "$app/Contents" ]] || exit 1
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == io.github.lincolnaleixo.retrolife ]] || { echo 'Unexpected bundle identifier.' >&2; exit 1; }
while IFS= read -r -d '' library; do
  lipo "$library" -verify_arch arm64
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$library"
done < <(find "$app/Contents" -name '*.dylib' -print0)
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
codesign --verify --deep --strict "$app"
output_dir=$(dirname "$app")
upload="$output_dir/notarization-upload.zip"
ditto -c -k --keepParent "$app" "$upload"
xcrun notarytool submit "$upload" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute "$app"
ditto -c -k --keepParent "$app" "$output_dir/RetroLife-macos-arm64.zip"
(cd "$output_dir" && shasum -a 256 RetroLife-macos-arm64.zip > SHA256SUMS)
