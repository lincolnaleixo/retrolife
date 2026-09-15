# Third-party notices

Original RetroLife source is AGPL-3.0-only. This does not relicense dependencies, game files, trademarks, or creative assets.

## bsnes-jg

Upstream: https://github.com/libretro/bsnes-jg

Pinned revision: `aa11568fff267fca3424cbdfa6da788ddc42e468`.

The core is GPL-3.0-or-later. Its incorporated byuuML, libco, libsamplerate, SameBoy and snes_spc components carry additional notices in `third-party/bsnes-jg/NOTICES`. The distribution must include these notices and corresponding core source. The core build script creates that source archive from the exact pinned Git tree.

## Rust and Godot

Cargo.lock records exact Rust dependencies. Release preparation must bundle their license texts and corresponding source where required. Godot retains its MIT notice and engine third-party notices. godot-rust 0.5.4 and gdextension-api are MPL-2.0, as declared by the locked crates; their corresponding source and MPL notice must accompany distribution. The libretro ABI declarations implement the public interface; any copied upstream header retains its MIT notice.

The MPL-covered Rust binding sources are additionally distributed under AGPL-3.0-only as part of this combined application under MPL 2.0 section 3.3; their original MPL rights and notices remain available. See [Mozilla's combination guidance](https://www.mozilla.org/en-US/MPL/2.0/FAQ/#q14-may-i-combine-mpl-licensed-code-and-lgpl-licensed-code-in-the-same-executable-program).

## Retro Cartridge Models

The neutral `snes-ntsc-u` cartridge, version `0.1.0`, is an independently versioned reconstruction by **Lincoln Aleixo** from https://github.com/lincolnaleixo/retro-cartridge-models.

Original model contributions retain **CC BY-NC-ND 4.0**, not the application's AGPL license. Attribution, noncommercial scope and restrictions on redistribution of adaptations remain in the upstream license. This integration makes no additional rights grant. Existing hardware designs, third-party artwork, marks and other material excluded in the upstream notice remain outside that license grant.

`assets/cartridges.lock.json` records the exact archive and selected-file hashes. The build stages the unchanged GLB with its `LICENSE`, `CREDITS.md`, `NOTICE.md` and machine-readable provenance. Exported application resources include these notices; macOS release preparation additionally places them in `Contents/Resources/licenses/retro-cartridge-models`. Release source includes the asset lock and staging tool so the same model inputs can be verified without placing creative binaries into the software Git history.

The neutral metadata label and procedural missing-model fallback are original application presentation code. User-selected PNG labels are local display overlays, not edits to or redistributed replacements of the pinned GLB. The textured Super Mario World example is not bundled.

## Game content

The application contains no Nintendo artwork, ROMs, BIOS or personal saves. User-imported games and labels are not distributed with the application. Synthetic UI test titles and generated test content are separate from the user's collection.
