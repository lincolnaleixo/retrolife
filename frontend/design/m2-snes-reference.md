# M2.1 NTSC-U SNES cartridge reference package

## Status

This package is the public provisional visual and envelope baseline for the early North American `SNS-006` wide-shell cartridge.

The M2 alpha and M2.2 v1 through v3 shapes are rejected as production geometry. The v2 reference corrects their visible proportions using authentic NTSC-U/C cartridge photography and USD343833S silhouette relationships. It still requires a physical specimen and digital-caliper measurements before M2.1 closes.

## Locked reference

- System: Super Nintendo Entertainment System
- Region: NTSC-U/C
- Shell family: early wide-shell `SNS-006`
- Patent embodiment: USD343833S first embodiment
- Coordinate origin: bottom connector center
- Units: millimetres
- Console geometry: forbidden

## Overall envelope

| Dimension | Baseline | Uncertainty | Confidence |
| --- | ---: | ---: | --- |
| Width | 136.0 mm | ±1.0 mm | A |
| Height | 88.0 mm | ±1.0 mm | A |
| Maximum depth | 20.0 mm | ±0.8 mm | A |
| Provisional front-shell depth | 10.4 mm | ±0.8 mm | B |

## Provisional front landmarks

| Landmark | Baseline | Uncertainty | Confidence |
| --- | ---: | ---: | --- |
| Central front-body width | 96.0 mm | ±2.0 mm | B |
| Central top width | 82.0 mm | ±2.0 mm | B |
| Side-wing width, each | 20.0 mm | ±1.5 mm | B |
| Side-wing top | Y 81.4 mm | ±0.8 mm | B |
| Label recess | 91.5 × 39.0 mm | ±1.5 mm | B |
| Label recess bottom | Y 47.0 mm | ±1.2 mm | B |
| Lower grip channel | 93.0 × 7.2 mm | ±2.0 / ±1.0 mm | B |
| Grip-channel center | Y 35.0 mm | ±1.5 mm | B |
| Screw centers | X ±56.0 mm, Y 6.8 mm | ±1.0 mm | B |
| Screw-well diameter | 6.1 mm | ±0.8 mm | C |

Four recessed side divisions are provisionally centred at Y 25.8, 42.0, 58.2 and 74.4 mm. They form five broad moulded bands on each side wing. This replaces the incorrect five-groove interpretation used by the rejected blockouts.

These relationships are scaled from the known envelope using USD343833S and authentic-cartridge photographs. They are not represented as caliper measurements.

## PCB and connector clearance

Open MouseBiteLabs boards establish the following internal constraints:

- PCB width range: 77.7 to 79.2 mm
- PCB length range: 110.2 to 116.2 mm
- PCB thickness: 1.2 mm
- gold-finger chamfer: 30 degrees

PCB values validate cavity and board clearance only. They do not define the exterior shell.

## Source authority

1. Nintendo USD343833S for front, rear, top, bottom and side relationships.
2. Authentic NTSC-U/C Super Mario World cartridge photography for the visible front-shell proportions.
3. Public-domain Evan-Amos cartridge photography for region and shell-family cross-checking.
4. CC BY-SA cartridge-bottom photography for connector and notch relationships.
5. MouseBiteLabs CC BY-SA 4.0 boards for internal PCB clearance.
6. Published NTSC Game Pak envelope dimensions.

No third-party image pixels or mesh vertices are embedded in the CC0 generated package.

## Physical validation still required

Before M2.1 closes, measure one authentic early NTSC-U/C cartridge and record:

- shell revision and photographed specimen
- overall width, height and maximum depth
- front and rear half depths
- central-body and top widths
- label recess dimensions, radius and depth
- lower grip-channel dimensions and bridge positions
- side-band division positions and depths
- screw-well coordinates and diameters
- connector mouth, bottom notches, top tabs and feet

Use a digital caliper with 0.1 mm resolution or better. Repeated readings and shell-revision variation must be recorded.

## M2.2 gate

M2.2 may continue as an original CAD B-rep rebuild from this package. Final approval, M2.3 and M3 remain blocked until physical calibration and explicit owner visual approval are recorded.
