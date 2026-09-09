#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/make-test-rom.py .cache/test.sfc
case "$(uname -s)" in
 Darwin) core=bsnes-jg_libretro.dylib ;;
 Linux) core=bsnes-jg_libretro.so ;;
 *) exit 1 ;;
esac
export RETROLIFE_TEST_CORE="$PWD/frontend/godot-ui/bin/$core"
export RETROLIFE_TEST_ROM="$PWD/.cache/test.sfc"
cargo test -p retrolife-emulation --locked --test real_core -- --ignored --nocapture
