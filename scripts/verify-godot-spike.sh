#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${1:-debug}"

# shellcheck source=scripts/lib/godot.sh
source "$repo_root/scripts/lib/godot.sh"

if ! godot_bin="$(retrolife_resolve_godot "$repo_root")"; then
    retrolife_print_godot_not_found
    exit 1
fi

if ! godot_version="$(retrolife_require_godot_version "$godot_bin" 4 7)"; then
    exit 1
fi

retrolife_cache_godot "$repo_root" "$godot_bin"

cd "$repo_root"

echo "RetroLife Phase 2 verification"
echo "Profile: $profile"
echo "Host: $(uname -s) $(uname -m)"
echo "Godot executable: $godot_bin"
echo "Godot version: $godot_version"
rustc --version
cargo --version

"$repo_root/scripts/build-godot-extension.sh" "$profile"

"$godot_bin" \
    --headless \
    --path "$repo_root/frontend/godot-ui" \
    --script res://scripts/smoke_test.gd

if [[ "${RETROLIFE_UI_SMOKE_WINDOWED:-0}" == "1" ]]; then
    if ! command -v xvfb-run >/dev/null 2>&1; then
        echo "RETROLIFE_UI_SMOKE_WINDOWED=1 requires xvfb-run." >&2
        exit 1
    fi
    RETROLIFE_POINTER_TEST=1 xvfb-run -a \
        "$godot_bin" \
        --display-driver x11 \
        --path "$repo_root/frontend/godot-ui" \
        --script res://scripts/ui_smoke_test.gd
else
    RETROLIFE_POINTER_TEST=0 "$godot_bin" \
        --headless \
        --path "$repo_root/frontend/godot-ui" \
        --script res://scripts/ui_smoke_test.gd
fi
