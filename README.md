# RetroLife

RetroLife is an experimental cross-platform retro-game frontend built with Godot 4.7 and Rust. Godot owns presentation and interaction, while the Rust crates own the catalog, launch contracts and native bridge boundaries.

This public repository contains only the new frontend source and its reproducible design assets. It does not contain the former private repository history, device configuration, deployment infrastructure, operational documentation, ROMs, BIOS files, saves, credentials, private media or emulator cores.

## Current scope

- Godot UI shell and deterministic smoke tests
- Platform-independent Rust domain models
- Godot GDExtension and launch bridges
- SNES-first visual and interaction contracts
- Original procedural M2 and M2.2 assets with their own CC0 notices

The M2.2 cartridge front is a provisional continuous-surface v2 rebuild. The earlier plate-stacked v1 blockout is rejected; physical calibration and owner approval are still required before v2 can be treated as final geometry.

## Build

Install the Rust toolchain declared in `rust-toolchain.toml` and Godot 4.7 or newer.

```bash
cargo test --workspace --locked
./scripts/build-phase4-launch.sh
./scripts/open-godot-editor.sh
```

The repository does not bundle games or emulator runtimes. You are responsible for providing software and content that you are legally entitled to use.

## Licensing and trademarks

The source code is publicly viewable but proprietary unless a file carries a separate license notice. See `LICENSE.md` and `THIRD_PARTY.md`.

RetroLife is an independent personal project. Nintendo, Super Nintendo, SNES and other names or marks belong to their respective owners. No affiliation or endorsement is claimed.
