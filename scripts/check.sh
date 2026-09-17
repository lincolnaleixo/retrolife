#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cargo fmt --all --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
python3 scripts/audit-publication.py
python3 scripts/check-dependencies.py
python3 scripts/test-cartridge-assets.py
python3 scripts/test-updates.py
python3 scripts/test-release-automation.py
scripts/build.sh
"${GODOT:-godot}" --headless --path frontend/godot-ui --editor --import

python3 scripts/make-test-rom.py .cache/test.sfc
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/cartridge_native_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/input_mapping_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/window_layout_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/cartridge_library_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/updater_smoke.gd
