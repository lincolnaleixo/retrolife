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
# Sparkle includes nested executable bundles, not just dylibs. Sign inside-out
# under the same Developer ID; do not disable Library Validation or use --deep
# as a substitute for explicitly signing the embedded components.
sparkle="$app/Contents/Frameworks/Sparkle.framework"
if [[ -d "$sparkle" ]]; then
  for relative in Versions/B/XPCServices/Downloader.xpc Versions/B/XPCServices/Installer.xpc Versions/B/Updater.app Versions/B/Autoupdate; do
    [[ -e "$sparkle/$relative" ]] || { echo 'Incomplete Sparkle framework.' >&2; exit 1; }
    if [[ "$relative" == Versions/B/XPCServices/Downloader.xpc ]]; then
      # Preserve the pinned downloader's entitlements, per upstream signing guidance.
      codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$SIGNING_IDENTITY" "$sparkle/$relative"
    else
      codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$sparkle/$relative"
    fi
  done
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$sparkle"
fi
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
