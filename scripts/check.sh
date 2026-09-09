#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cargo fmt --all --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
python3 scripts/audit-publication.py
python3 scripts/check-dependencies.py
scripts/build.sh
"${GODOT:-godot}" --headless --path frontend/godot-ui --editor --import

python3 scripts/make-test-rom.py .cache/test.sfc
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/local_library_smoke.gd
"${GODOT:-godot}" --headless --path frontend/godot-ui --script res://scripts/input_mapping_smoke.gd
