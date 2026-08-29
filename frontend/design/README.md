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

The first procedural cartridge and M2.2 v1 through v4 are rejected as production geometry. M2.1 reference v3 records a new visual recalibration of the provisional envelope and landmarks. M2.2 v5 builds the active front shell as a CadQuery/Open CASCADE boundary-representation solid with a lower shoulder rise, broader side wings, a nearly flush central face and shallow molded details.

The primary engineering artifact is the STEP file. The Godot runtime uses the deterministic OBJ tessellation. Mobile review uses PNG renders made from the generated CAD tessellation. The label visible in the review PNGs is original RetroLife review artwork and is not part of the runtime asset. SVG remains useful for dimensions, but it is not the primary M2.2 geometry or review medium.

Validate the current package with:

```bash
python3 -m pip install -r scripts/requirements-m2-cad.txt
python3 scripts/verify-m2-snes-reference.py
python3 scripts/generate-m2-2-snes-front.py --check --skip-renders
python3 scripts/verify-m2-2-snes-front.py
```

The normal product flow displays no console. Confirm seats the selected cartridge into the fixed bottom dock. Back reverses the transition and restores exact context and semantic focus.

## Mobile review

The active mobile sheet is `mobile/m2-2-snes-v5-mobile-review.png`. It is a direct render of the committed v5 CAD tessellation and is intended for mobile browsers that do not display engineering files reliably.

Physical calibration and explicit owner approval remain open. M2.3 and M3 stay blocked until those gates close.
