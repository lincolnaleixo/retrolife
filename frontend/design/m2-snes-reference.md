# M2.1 NTSC-U SNES cartridge reference package

## Status

This package is the public provisional visual baseline for the early North American `SNS-006` wide-shell cartridge.

Reference v3 replaces the visibly incorrect v2 front proportions. It was normalized against a clean frontal photograph of an authentic NTSC-U/C cartridge and cross-checked against the front, top and side relationships in USD343833S. It still requires a physical specimen and digital-caliper measurements before M2.1 closes.

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
| Provisional front-shell depth | 10.0 mm | ±0.8 mm | B |

## Provisional front landmarks

| Landmark | Baseline | Uncertainty | Confidence |
| --- | ---: | ---: | --- |
| Central front-body width | 92.0 mm | ±1.5 mm | B |
| Central top width | 84.0 mm | ±1.5 mm | B |
| Side-wing width, each | 22.0 mm | ±1.0 mm | B |
| Side-wing top | Y 83.0 mm | ±0.8 mm | B |
| Label recess | 84.5 × 38.0 mm | ±1.2 mm | B |
| Label recess bottom | Y 45.0 mm | ±1.0 mm | B |
| Lower grip field | 87.0 × 6.3 mm | ±1.5 / ±0.8 mm | B |
| Grip-field center | Y 29.8 mm | ±1.2 mm | B |
| Central grip bridge | 18.0 mm | ±2.0 mm | B |
| Screw centers | X ±56.7 mm, Y 7.4 mm | ±0.8 mm | B |
| Screw-well diameter | 5.2 mm | ±0.6 mm | C |

Four narrow recessed divisions are provisionally centred at Y 24.3, 38.8, 53.3 and 67.8 mm. They create five broad molded bands on each side wing. This replaces the high, over-spaced divisions used by the rejected v4 shell.

The visual ratio checks recorded in the manifest are:

- central body to overall width: 0.676471
- label to overall width: 0.621324
- side-wing top drop to overall height: 0.056818
- grip field to overall width: 0.639706

These are photo-normalized relationships, not caliper measurements.

## PCB and connector clearance

Open MouseBiteLabs boards establish the following internal constraints:

- PCB width range: 77.7 to 79.2 mm
- PCB length range: 110.2 to 116.2 mm
- PCB thickness: 1.2 mm
- gold-finger chamfer: 30 degrees

PCB values validate cavity and board clearance only. They do not define the exterior shell.

## Source authority

1. Nintendo USD343833S for front, rear, top, bottom and side relationships.
2. Authentic NTSC-U/C frontal cartridge photography for normalized visible proportions.
3. Public-domain Evan-Amos cartridge photography for region and shell-family cross-checking.
4. CC BY-SA cartridge-bottom photography for connector and notch relationships.
5. MouseBiteLabs CC BY-SA 4.0 boards for internal PCB clearance.
6. Published NTSC Game Pak envelope dimensions.

No third-party photograph pixels or mesh vertices are embedded in the CC0 generated package.

## Physical validation still required

Before M2.1 closes, measure one authentic early NTSC-U/C cartridge and record:

- shell revision and photographed specimen
- overall width, height and maximum depth
- front and rear half depths
- central-body and top widths
- label recess dimensions, radius and depth
- lower grip dimensions and bridge width
- side-band division positions and depths
- screw-well coordinates and diameters
- connector mouth, bottom notches, top tabs and feet

Use a digital caliper with 0.1 mm resolution or better. Repeated readings and shell-revision variation must be recorded.

## M2.2 gate

M2.2 may continue as an original CAD B-rep rebuild from this package. Final approval, M2.3 and M3 remain blocked until physical calibration and explicit owner visual approval are recorded.
