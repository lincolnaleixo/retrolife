#!/usr/bin/env bash
# Pinned official engine and export templates. No unverified installer or action.
set -euo pipefail
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]]
root=${RUNNER_TEMP:-$PWD/.cache}/retrolife-godot
mkdir -p "$root"
base=https://github.com/godotengine/godot/releases/download/4.7.2-stable
curl --fail --location --retry 3 "$base/Godot_v4.7.2-stable_macos.universal.zip" -o "$root/engine.zip"
echo "c58a24e31d720be9d62f60cb5627c4e695fb72f21b0cfe1bc9ccaa9a3b3ba63e  $root/engine.zip" | shasum -a 256 --check
unzip -qo "$root/engine.zip" -d "$root/engine"
curl --fail --location --retry 3 "$base/Godot_v4.7.2-stable_export_templates.tpz" -o "$root/templates.tpz"
echo "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011  $root/templates.tpz" | shasum -a 256 --check
# Only extract the macOS template; no need to install the other platforms.
unzip -qo "$root/templates.tpz" 'templates/macos.zip' -d "$root"
template_dir="$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable"
mkdir -p "$template_dir"
cp "$root/templates/macos.zip" "$template_dir/macos.zip"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "GODOT=$root/engine/Godot.app/Contents/MacOS/Godot" >> "$GITHUB_ENV"
fi
printf 'Pinned Godot and macOS export template installed.\n'
