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
python3 scripts/test-release-verification.py
python3 scripts/test-local-macos-install.py
scripts/build.sh
"${GODOT:-godot}" --headless --path frontend/godot-ui --editor --import

python3 scripts/make-test-rom.py .cache/test.sfc
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/cartridge_native_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/input_mapping_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/window_layout_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/cartridge_library_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/media_model_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/updater_smoke.gd
if [[ "${RETROLIFE_ASSET_MODE:-public-neutral}" == public-neutral && "${RETROLIFE_SKIP_CARTRIDGE_ASSETS:-0}" != 1 ]]; then
    "${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/public_assets_smoke.gd
fi

"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/workspace_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/journey_art_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/game_presentation_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/gameplay_window_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/rewards_center_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/library_presentation_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/collection_flow_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/library/collectible_pair_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/gameplay_input_ownership_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/gameplay_shader_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/gameplay_settings_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/selection_media_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/save_states_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/save_states_native_smoke.gd
