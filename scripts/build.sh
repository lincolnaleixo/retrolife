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
