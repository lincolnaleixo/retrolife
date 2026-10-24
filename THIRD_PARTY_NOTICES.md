# Third-party notices

Original RetroLife source is AGPL-3.0-only. This does not relicense dependencies, game files, trademarks, or creative assets.

## bsnes-jg

Upstream: https://github.com/libretro/bsnes-jg

Pinned revision: `aa11568fff267fca3424cbdfa6da788ddc42e468`.

The core is GPL-3.0-or-later. Its incorporated byuuML, libco, libsamplerate, SameBoy and snes_spc components carry additional notices in `third-party/bsnes-jg/NOTICES`. The distribution must include these notices and corresponding core source. The core build script creates that source archive from the exact pinned Git tree.

## Rust and Godot

Cargo.lock records exact Rust dependencies. Release preparation must bundle their license texts and corresponding source where required. Godot retains its MIT notice and engine third-party notices. godot-rust 0.5.4 and gdextension-api are MPL-2.0, as declared by the locked crates; their corresponding source and MPL notice must accompany distribution. The libretro ABI declarations implement the public interface; any copied upstream header retains its MIT notice.

The MPL-covered Rust binding sources are additionally distributed under AGPL-3.0-only as part of this combined application under MPL 2.0 section 3.3; their original MPL rights and notices remain available. See [Mozilla's combination guidance](https://www.mozilla.org/en-US/MPL/2.0/FAQ/#q14-may-i-combine-mpl-licensed-code-and-lgpl-licensed-code-in-the-same-executable-program).

## Private Retro 3D Library (not bundled)

Public releases contain no files from the private Retro 3D Library. The following records apply only to explicit owner-side staging of historical packages, not to the public app’s procedural presentation.

The neutral `snes-ntsc-u`, `mega-drive`, `playstation-1`, `nintendo-64` and `nes` models are independently versioned reconstructions by **Lincoln Aleixo** from [Retro 3D Library](https://github.com/lincolnaleixo/retro-3d-library).

The historical locked packages carry their independent **CC BY-NC-ND 4.0** notices, not the application's AGPL license. Keep their original notices with any explicit owner-side staging. The private collection is not part of this release and this integration grants no additional rights to it, hardware designs, third-party artwork or marks.

`assets/cartridges.lock.json` and `assets/media-models.lock.json` retain historical versions, archive hashes and selected-file hashes for explicit owner-mode validation. That mode stages unchanged GLBs with their independent notices and provenance. The public release builder rejects such a stage. Its `Contents/Resources/licenses/retrolife-assets.json` and release asset declaration record `public-neutral` and no bundled external models. Release source retains the validation code and historical locks, without creative model binaries.

The neutral metadata label and procedural missing-model fallback are original application presentation code. User-selected PNG labels are local display overlays, not edits to or redistributed replacements of the pinned GLB. Textured game reproductions are not bundled. Approved label exports from the collection can be downloaded on request into the user's local cache and are verified against the collection's published checksums; they are not part of application source, releases or public evidence.

## Game content

The application contains no Nintendo artwork, ROMs, BIOS or personal saves. User-imported games and labels are not distributed with the application. Synthetic UI test titles and generated test content are separate from the user's collection.

## Sparkle

The macOS updater embeds Sparkle 2.10.0 from https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0 under its upstream permissive license and included component notices. The exact official SDK is checksum-pinned by `scripts/prepare-sparkle.py`; its complete LICENSE is distributed as `Contents/Resources/licenses/Sparkle-LICENSE` in the app. The updater test host, ephemeral signing seeds and test-only trust exceptions are never distributed. Sparkle is not relicensed by the application license.

## ZIP archive support

ZIP reading uses zip 9.1.0 under MIT with the Deflate backend recorded in Cargo.lock. The transitive, UEFI-only r-efi 6.0.0 package offers MIT OR Apache-2.0 OR LGPL-2.1-or-later; RetroLife selects its MIT option. The corresponding-source dependency bundle preserves upstream license files.
