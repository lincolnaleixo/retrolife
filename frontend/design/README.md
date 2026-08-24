# RetroLife design contracts

The active production visual reference is SNES-first. These files describe the public, reproducible design contract for the current frontend.

## M1 interaction contract

The M1 package fixes the viewport, states, semantic focus, motion, reduced-motion behavior and bottom dock composition:

- `m1-snes-contract.md` and `m1-snes-contract.json`
- `m1-snes-golden-frames.svg`
- `m1-snes-motion-storyboard.svg`

Validate it with:

```bash
python3 scripts/verify-m1-snes-contract.py
```

## M2 cartridge rebuild

The first procedural cartridge remains an engineering blockout and is rejected as final geometry. The replacement is built from an authentic NTSC-U reference contract without third-party meshes, photos, branding, artwork or ROM content.

The M2.1 package records the provisional dimensions, confidence levels and remaining physical-calibration gate. The M2.2 package provides a deterministic clean-room front shell and Godot scene. Both remain provisional until physical calibration and explicit owner review are complete.

Validate them with:

```bash
python3 scripts/verify-m2-snes-reference.py
python3 scripts/generate-m2-2-snes-front.py --check
python3 scripts/verify-m2-2-snes-front.py
```

The normal product flow displays no console. Confirm seats the selected cartridge into the fixed bottom dock. Back reverses the transition and restores exact context and semantic focus.
