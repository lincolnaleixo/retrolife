#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
revision=aa11568fff267fca3424cbdfa6da788ddc42e468
source_dir=.cache/bsnes-jg
mkdir -p .cache frontend/godot-ui/bin
if [[ ! -d "$source_dir/.git" ]]; then
  git clone --no-checkout https://github.com/libretro/bsnes-jg.git "$source_dir"
  git -C "$source_dir" checkout --detach "$revision"
fi
[[ -z "$(git -C "$source_dir" status --porcelain --untracked-files=no)" ]] || { echo 'Core source has local modifications.' >&2; exit 1; }
git -C "$source_dir" checkout --detach "$revision"
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$revision" ]]
case "$(uname -s)" in
  Darwin)
    [[ "$(uname -m)" == arm64 ]] || { echo 'Release core requires Apple Silicon.' >&2; exit 1; }
    export MACOSX_DEPLOYMENT_TARGET=13.0
    make -C "$source_dir/libretro" -j"${JOBS:-2}" platform=osx arch=arm64 MINVERSION=-mmacosx-version-min=13.0 ARCHFLAGS=-arch\ arm64
    library=bsnes-jg_libretro.dylib
    lipo "$source_dir/libretro/$library" -verify_arch arm64
    ;;
  Linux)
    make -C "$source_dir/libretro" -j"${JOBS:-2}" platform=unix
    library=bsnes-jg_libretro.so
    ;;
  *) echo 'Unsupported build platform.' >&2; exit 1 ;;
esac
cp "$source_dir/libretro/$library" frontend/godot-ui/bin/
mkdir -p dist/core-source
git -C "$source_dir" archive --format=tar.gz --prefix=bsnes-jg/ "$revision" > dist/core-source/bsnes-jg.tar.gz
