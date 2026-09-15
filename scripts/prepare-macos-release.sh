#!/usr/bin/env bash
# Build locally on the trusted signing machine. Does not publish or create tags.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo 'Apple Silicon macOS is required.' >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit reviewed source before preparing a release.' >&2; exit 1; }
version=${1:?Pass a release version such as 0.1.0-beta.3}
# Validate before building or touching the signing environment.
PYTHONPATH=scripts python3 -c 'from updates.common import version_info; import sys; version_info(sys.argv[1])' "$version"
export MACOSX_DEPLOYMENT_TARGET=13.0
scripts/build-macos-updater.sh
sdk="$PWD/.cache/sparkle/2.10.0"
account=${SPARKLE_KEY_ACCOUNT:-io.github.lincolnaleixo.retrolife.sparkle}
# Creates once, then reuses the private key in the trusted machine's Keychain.
# Only the public key is printed or embedded in the app.
"$sdk/bin/generate_keys" --account "$account"
public_key=$("$sdk/bin/generate_keys" --account "$account" -p)
scripts/build-core.sh
scripts/check.sh
scripts/test-core.sh
# A fallback-only development build is not a cartridge-library release.
python3 scripts/prepare-cartridge-assets.py --verify-only
export CARGO_ENCODED_RUSTFLAGS
CARGO_ENCODED_RUSTFLAGS=$(printf '%s\037%s' "--remap-path-prefix=$PWD=." "--remap-path-prefix=$HOME=~")
cargo build --release --locked -p retrolife-godot
cp target/release/libretrolife_godot.dylib frontend/godot-ui/bin/
mkdir -p dist
release_dir=$(mktemp -d "$(pwd)/dist/macos.XXXXXX")
"${GODOT:-godot}" --headless --path frontend/godot-ui --export-release 'macOS Apple Silicon' "$release_dir/RetroLife.zip"
unzip "$release_dir/RetroLife.zip" -d "$release_dir"
app="$release_dir/RetroLife.app"
[[ -d "$app/Contents" ]]
# Official Godot templates are universal; ship only the arm64 engine slice.
engine="$app/Contents/MacOS/RetroLife"
lipo "$engine" -thin arm64 -output "$engine.arm64"
mv "$engine.arm64" "$engine"
lipo "$engine" -verify_arch arm64
mkdir -p "$app/Contents/Frameworks" "$app/Contents/Resources/licenses"
ditto "$sdk/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp .cache/updater-build/libretrolife_updater.dylib "$app/Contents/Frameworks/"
python3 scripts/configure-updater-bundle.py "$app" "$version" "$public_key"
cp frontend/godot-ui/bin/bsnes-jg_libretro.dylib "$app/Contents/Frameworks/"
# Rust source remapping does not rewrite Mach-O library install names.
install_name_tool -id @rpath/libretrolife_godot.dylib "$app/Contents/Frameworks/libretrolife_godot.dylib"
install_name_tool -id @rpath/bsnes-jg_libretro.dylib "$app/Contents/Frameworks/bsnes-jg_libretro.dylib"
cp LICENSE NOTICE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/licenses/"
cp -R third-party "$app/Contents/Resources/licenses/"
cp "$sdk/LICENSE" "$app/Contents/Resources/licenses/Sparkle-LICENSE"
asset_notices="$app/Contents/Resources/licenses/retro-cartridge-models"
mkdir -p "$asset_notices"
for name in LICENSE CREDITS.md NOTICE.md provenance.json; do
    cp "frontend/godot-ui/assets/cartridges/$name" "$asset_notices/"
done
cp assets/cartridges.lock.json dist/retrolife-cartridge-assets.lock.json
cargo vendor --locked dist/vendor > dist/vendor-config.toml
# The vendor archive contains each dependency's upstream license and source.
tar -czf dist/retrolife-rust-dependencies.tar.gz -C dist vendor vendor-config.toml
git archive --format=tar.gz --prefix=retrolife/ HEAD > dist/retrolife-source.tar.gz
scripts/sign-macos.sh "$app"
python3 scripts/prepare-update-metadata.py "$app" "$release_dir/RetroLife-macos-arm64.zip" --account "$account"
(cd "$release_dir" && shasum -a 256 retrolife-update.json >> SHA256SUMS)
"$app/Contents/MacOS/RetroLife" --headless --quit-after 5
echo 'Prepared locally. Native acceptance and artifact review are required before publication.'
