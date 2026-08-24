#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${1:-debug}"

case "$profile" in
  debug)
    cargo_profile_args=()
    target_profile="debug"
    ;;
  release)
    cargo_profile_args=(--release)
    target_profile="release"
    ;;
  *)
    echo "Usage: $0 [debug|release]" >&2
    exit 2
    ;;
esac

cd "$repo_root"

"$repo_root/scripts/build-godot-extension.sh" "$profile"
cargo test -p retrolife-core --locked
cargo test -p retrolife-launch-bridge --locked
cargo build -p retrolife-launch-fixture --locked "${cargo_profile_args[@]}"
cargo build -p retrolife-launch-bridge --locked "${cargo_profile_args[@]}"

mkdir -p "$repo_root/frontend/godot-ui/bin"
case "$(uname -s)" in
  Darwin)
    source_library="$repo_root/target/$target_profile/libretrolife_launch_bridge.dylib"
    destination="$repo_root/frontend/godot-ui/bin/libretrolife_launch_bridge.dylib"
    ;;
  Linux)
    source_library="$repo_root/target/$target_profile/libretrolife_launch_bridge.so"
    destination="$repo_root/frontend/godot-ui/bin/libretrolife_launch_bridge.so"
    ;;
  *)
    echo "Unsupported host for the Phase 4 launch bridge: $(uname -s)" >&2
    exit 1
    ;;
esac

cp "$source_library" "$destination"
echo "Built ${destination#$repo_root/}"
echo "Launch fixture: target/$target_profile/retrolife-launch-fixture"
