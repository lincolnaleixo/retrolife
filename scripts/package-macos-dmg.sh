#!/usr/bin/env bash
# Package an already signed and stapled app; no application rebuild or publication.
set -euo pipefail
: "${SIGNING_IDENTITY:?Set a Developer ID identity}"
: "${NOTARY_PROFILE:?Set a Keychain notary profile}"
app=${1:?Pass the signed RetroLife.app path}
output=${2:?Pass a new output directory}
[[ ! -e "$output" ]] || { echo 'Output must not exist.' >&2; exit 1; }
codesign --verify --deep --strict "$app"
xcrun stapler validate "$app"
mkdir -p "$output/payload"
ditto "$app" "$output/payload/RetroLife.app"
ln -s /Applications "$output/payload/Applications"
dmg="$output/RetroLife-macos-arm64.dmg"
hdiutil create -volname RetroLife -srcfolder "$output/payload" -format UDZO "$dmg"
codesign --timestamp --sign "$SIGNING_IDENTITY" "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
codesign --verify --strict "$dmg"
spctl --assess --type open --context context:primary-signature "$dmg"
hdiutil verify "$dmg"
(cd "$output" && shasum -a 256 RetroLife-macos-arm64.dmg > SHA256SUMS)
