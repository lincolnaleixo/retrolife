#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cargo build --locked -p retrolife-godot
mkdir -p frontend/godot-ui/bin
case "$(uname -s)" in
 Darwin) cp target/debug/libretrolife_godot.dylib frontend/godot-ui/bin/ ;;
 Linux) cp target/debug/libretrolife_godot.so frontend/godot-ui/bin/ ;;
 *) echo 'Unsupported development platform.' >&2; exit 1 ;;
esac

# Load the built extension at startup, before first editor discovery.
# Godot 4.7.2 can crash on shutdown after discovering it late during import.
mkdir -p frontend/godot-ui/.godot
printf '%s\n' 'res://retrolife.gdextension' > frontend/godot-ui/.godot/extension_list.cfg
