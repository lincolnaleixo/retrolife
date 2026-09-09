# Third-party notices

Original RetroLife source is AGPL-3.0-only. This does not relicense dependencies, game files, trademarks, or creative assets.

## bsnes-jg

Upstream: https://github.com/libretro/bsnes-jg

Pinned revision: `aa11568fff267fca3424cbdfa6da788ddc42e468`.

The core is GPL-3.0-or-later. Its incorporated byuuML, libco, libsamplerate, SameBoy and snes_spc components carry additional notices in `third-party/bsnes-jg/NOTICES`. The distribution must include these notices and corresponding core source. The core build script creates that source archive from the exact pinned Git tree.

## Rust and Godot

Cargo.lock records exact Rust dependencies. Release preparation must bundle their license texts and corresponding source where required. Godot retains its MIT notice and engine third-party notices. godot-rust 0.5.4 and gdextension-api are MPL-2.0, as declared by the locked crates; their corresponding source and MPL notice must accompany distribution. The libretro ABI declarations implement the public interface; any copied upstream header retains its MIT notice.

The MPL-covered Rust binding sources are additionally distributed under AGPL-3.0-only as part of this combined application under MPL 2.0 section 3.3; their original MPL rights and notices remain available. See [Mozilla’s combination guidance](https://www.mozilla.org/en-US/MPL/2.0/FAQ/#q14-may-i-combine-mpl-licensed-code-and-lgpl-licensed-code-in-the-same-executable-program).

## Creative assets and game content

The separate https://github.com/lincolnaleixo/retro-cartridge-models collection has its own licenses. This application baseline contains no Nintendo artwork, ROMs, BIOS, or personal saves. User-imported content is not distributed with the application.
