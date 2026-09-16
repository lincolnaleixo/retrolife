#!/usr/bin/env bash
# Build and test without access to any production private key.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]]
[[ -z "$(git status --porcelain)" ]] || { echo 'A clean reviewed checkout is required.' >&2; exit 1; }
version=${1:?Pass a release version}
public_key=${2:?Pass the persistent Sparkle PUBLIC key}
PYTHONPATH=scripts python3 -c 'from updates.common import version_info,decode_key; import sys; version_info(sys.argv[1]);decode_key(sys.argv[2],32)' "$version" "$public_key"
export MACOSX_DEPLOYMENT_TARGET=13.0
# Apply path remapping to debug checks too, so packaged native binaries cannot
# leak a runner's local checkout path.
export CARGO_ENCODED_RUSTFLAGS
CARGO_ENCODED_RUSTFLAGS=$(printf '%s\037%s' "--remap-path-prefix=$PWD=." "--remap-path-prefix=$HOME=~")
scripts/build-macos-updater.sh
sdk="$PWD/.cache/sparkle/2.10.0"
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
release_dir="$PWD/dist/unsigned"
[[ ! -e "$release_dir" ]] || { echo "Unsigned output already exists." >&2; exit 1; }
mkdir -p "$release_dir"
"${GODOT:-godot}" --headless --path frontend/godot-ui --export-release 'macOS Apple Silicon' "$release_dir/RetroLife.zip"
unzip "$release_dir/RetroLife.zip" -d "$release_dir"
app="$release_dir/RetroLife.app"
[[ -d "$app/Contents" ]]
# Official Godot templates are universal; ship only the arm64 engine slice.
engine="$app/Contents/MacOS/RetroLife"
if [[ "$(lipo -archs "$engine")" != arm64 ]]; then
  lipo "$engine" -thin arm64 -output "$engine.arm64"
  mv "$engine.arm64" "$engine"
fi
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
cp dist/core-source/bsnes-jg.tar.gz dist/
cp dist/retrolife-*.tar.gz dist/bsnes-jg.tar.gz dist/retrolife-cartridge-assets.lock.json "$release_dir/"
cp LICENSE NOTICE THIRD_PARTY_NOTICES.md "$release_dir/"
rm "$release_dir/RetroLife.zip"
echo "Unsigned application and corresponding source prepared; not a distributable release."
