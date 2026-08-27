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

The first procedural cartridge and M2.2 v1 through v3 are rejected as production geometry. M2.1 v2 records the visual-calibrated provisional envelope and landmarks. M2.2 v4 builds the active front shell as a CadQuery/Open CASCADE boundary-representation solid with drafted boolean features.

The primary engineering artifact is the STEP file. The Godot runtime uses the deterministic OBJ tessellation. Mobile review uses PNG renders made from the generated CAD tessellation. SVG is no longer the primary M2.2 geometry or review medium.

Validate the current package with:

```bash
python3 -m pip install -r scripts/requirements-m2-cad.txt
python3 scripts/verify-m2-snes-reference.py
python3 scripts/generate-m2-2-snes-front.py --check --skip-renders
python3 scripts/verify-m2-2-snes-front.py
```

The normal product flow displays no console. Confirm seats the selected cartridge into the fixed bottom dock. Back reverses the transition and restores exact context and semantic focus.

## Mobile review

The active mobile sheet is `mobile/m2-2-snes-v4-mobile-review.png`. It is a direct render of the committed v4 CAD tessellation and is intended for mobile browsers that do not display engineering files reliably.

Physical calibration and explicit owner approval remain open. M2.3 and M3 stay blocked until those gates close.
