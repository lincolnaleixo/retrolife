#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${1:-debug}"

case "$profile" in
    debug)
        profile_dir="debug"
        ;;
    release)
        profile_dir="release"
        ;;
    *)
        echo "Usage: $0 [debug|release]" >&2
        exit 2
        ;;
esac

case "$(uname -s)" in
    Darwin)
        library="libretrolife_godot.dylib"
        ;;
    Linux)
        library="libretrolife_godot.so"
        ;;
    *)
        echo "Unsupported development host: $(uname -s)" >&2
        exit 1
        ;;
esac

cd "$repo_root"

cargo test -p retrolife-core --locked

if [[ "$profile" == "release" ]]; then
    cargo build -p retrolife-godot --release --locked
else
    cargo build -p retrolife-godot --locked
fi

mkdir -p frontend/godot-ui/bin
cp "target/${profile_dir}/${library}" "frontend/godot-ui/bin/${library}"

echo "Built frontend/godot-ui/bin/${library}"
echo "Verified the committed frontend source package."
echo "Open frontend/godot-ui/project.godot with Godot 4.7 or newer."
