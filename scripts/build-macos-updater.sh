#!/usr/bin/env bash
# No credentials are used: the containing app signs these components later.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo 'Apple Silicon macOS is required.' >&2; exit 1; }
sdk=$(python3 scripts/prepare-sparkle.py "$@")
mkdir -p .cache/updater-build
xcrun clang -arch arm64 -mmacosx-version-min=13.0 -fobjc-arc -fblocks \
    -Wall -Wextra -Werror -Wno-unused-parameter -dynamiclib \
    -F "$sdk" -framework Cocoa -framework Security -framework Sparkle \
    -Wl,-rpath,@loader_path -Wl,-install_name,@rpath/libretrolife_updater.dylib \
    native/macos/updater.m -o .cache/updater-build/libretrolife_updater.dylib
# The copy is made by prepare-macos-release.sh with ditto to retain symlinks.
echo 'Built native updater; embed it with the pinned Sparkle framework before app signing.'
