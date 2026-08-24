#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

echo "Opening RetroLife with Godot $godot_version"
echo "Godot executable: $godot_bin"
echo "M2.2 SNES front shell: using the committed deterministic CC0 package"

exec "$godot_bin" \
    --editor \
    --path "$repo_root/frontend/godot-ui" \
    "$@"
