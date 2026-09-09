#!/usr/bin/env bash
# Build locally on the trusted signing machine. Does not publish or create tags.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo 'Apple Silicon macOS is required.' >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit reviewed source before preparing a release.' >&2; exit 1; }
export MACOSX_DEPLOYMENT_TARGET=13.0
scripts/build-core.sh
scripts/check.sh
scripts/test-core.sh
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
mkdir -p "$app/Contents/Frameworks" "$app/Contents/Resources/licenses"
cp frontend/godot-ui/bin/bsnes-jg_libretro.dylib "$app/Contents/Frameworks/"
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/licenses/"
cp -R third-party "$app/Contents/Resources/licenses/"
cargo vendor --locked dist/vendor > dist/vendor-config.toml
# The vendor archive contains each dependency's upstream license and source.
tar -czf dist/retrolife-rust-dependencies.tar.gz -C dist vendor vendor-config.toml
git archive --format=tar.gz --prefix=retrolife/ HEAD > dist/retrolife-source.tar.gz
scripts/sign-macos.sh "$app"
echo 'Prepared locally. Native acceptance and artifact review are required before publication.'
