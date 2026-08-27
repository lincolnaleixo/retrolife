# RetroLife

RetroLife is an experimental cross-platform retro-game frontend built with Godot 4.7 and Rust. Godot owns presentation and interaction, while the Rust crates own the catalog, launch contracts and native bridge boundaries.

This public repository contains only the new frontend source and its reproducible design assets. It does not contain the former private repository history, device configuration, deployment infrastructure, operational documentation, ROMs, BIOS files, saves, credentials, private media or emulator cores.

## Current scope

- Godot UI shell and deterministic smoke tests
- Platform-independent Rust domain models
- Godot GDExtension and launch bridges
- SNES-first visual and interaction contracts
- Original procedural M2 and CadQuery/Open CASCADE M2.2 v5 assets with their own CC0 notices

The M2.2 v1 plate stack, v2 height field, v3 loft-only presentation and visually rejected v4 CAD shell are retained only in public history. The active v5 front shell is a photo-normalized provisional CAD B-rep with STEP, STL, OBJ and mobile PNG review artifacts. Physical caliper calibration and explicit owner approval are still required before it can be treated as final geometry.

## Build

Install the Rust toolchain declared in `rust-toolchain.toml`, Python 3.12 or newer, the pinned CAD requirements and Godot 4.7 or newer.

```bash
python3 -m pip install -r scripts/requirements-m2-cad.txt
cargo test --workspace --locked
python3 scripts/generate-m2-2-snes-front.py --check --skip-renders
python3 scripts/verify-m2-2-snes-front.py
./scripts/build-phase4-launch.sh
./scripts/open-godot-editor.sh
```

Before pushing a public branch, run the complete local gate after committing the intended changes:

```bash
GODOT_BIN=/path/to/godot GITLEAKS_BIN=/path/to/gitleaks ./scripts/verify-before-push.sh
```

The repository does not bundle games or emulator runtimes. You are responsible for providing software and content that you are legally entitled to use.

## Licensing and trademarks

The source code is publicly viewable but proprietary unless a file carries a separate license notice. See `LICENSE.md` and `THIRD_PARTY.md`.

RetroLife is an independent personal project. Nintendo, Super Nintendo, SNES and other names or marks belong to their respective owners. No affiliation or endorsement is claimed.
