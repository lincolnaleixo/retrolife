# M2.1 NTSC-U SNES cartridge reference package

## Status

This package replaces visual guesswork with a reproducible provisional baseline for the early North American `SNS-006` wide-shell cartridge.

The current M2 procedural cartridge is classified as `M2-alpha-blockout`. It is excluded as a production shape reference.

The package is strong enough to begin M2.2 blockout and topology, but M2.1 remains open until the provisional B and C measurements are spot-checked against one authentic cartridge with digital calipers.

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

The envelope comes from the published NTSC Game Pak dimensions and is cross-checked against patent and authentic-cartridge photography.

## Provisional anatomical landmarks

| Landmark | Baseline | Uncertainty | Confidence |
| --- | ---: | ---: | --- |
| Central upper body width | 83.0 mm | ±2.0 mm | B |
| Side-wing width, each | 26.5 mm | ±1.0 mm | B |
| Side-wing top drop | 6.5 mm | ±1.0 mm | B |
| Label recess | 83.0 × 38.5 mm | ±1.5 / ±2.0 mm | B |
| Label recess bottom | 47.0 mm above connector origin | ±1.5 mm | B |
| Lower-front grip field | 83.0 × 37.0 mm | ±1.5 / ±2.0 mm | B |
| Screw centers | X ±54.5 mm, Y 10.0 mm | ±1.0 mm | B |
| Connector mouth | 88.0 × 7.0 mm | ±2.0 / ±1.0 mm | B |
| Rear warning field | 83.0 × 28.0 mm | ±2.0 mm | B |

Five horizontal groove centers are provisionally located at Y 17.5, 31.5, 45.5, 59.5, and 73.5 mm on each side wing.

These values are scaled from the known envelope using USD343833S orthographic relationships and open authentic-cartridge photographs. They are not presented as caliper measurements.

## PCB clearance

Open MouseBiteLabs boards establish the following internal constraints:

- PCB width range: 77.7 to 79.2 mm
- PCB length range: 110.2 to 116.2 mm
- PCB thickness: 1.2 mm
- gold-finger chamfer: 30 degrees

PCB values validate cavity and board clearance only. They do not define the exterior shell.

## Tolerance classes

- critical connector and dock landmarks: 0.6 mm
- overall envelope: 1.0 mm
- major silhouette landmarks: 1.5 mm
- label recess: 1.0 mm
- decorative moulded detail: 2.0 mm

Physical caliper results replace provisional B and C values. They do not change the approved M1 pivot, dock path, state machine, or visibility rule.

## Alpha rejection record

The alpha got the rough envelope close, but its anatomy is unsuitable:

- height is 1.8 percent short
- label recess is about 19.5 percent too short vertically
- side wings are narrow add-on prisms instead of broad shell masses
- side grips are ladder-like ribs instead of full-width horizontal grooves
- the lower-front field is far too small
- the rear is a generic inset panel
- the connector is not a true recessed cavity

See `m2-snes-alpha-deviation.svg` and the machine-readable `alphaDeviation` section in the manifest.

## Source authority

1. Nintendo design patent USD343833S for the complete orthographic relationship.
2. Nintendo design patent family member USD344504S for perspective cross-checking.
3. Public-domain Evan-Amos cartridge photography for the NTSC-U silhouette.
4. CC BY-SA Anomie bottom photography for the connector and notches.
5. MouseBiteLabs CC BY-SA 4.0 boards for PCB and gold-finger constraints.
6. Published NTSC Game Pak envelope dimensions.

The repository does not embed third-party photographs in this CC0 reference package. The SVGs are original diagrams derived from the recorded dimensions and relationships.

## Physical validation still required

Before M2.1 closes, measure one authentic early NTSC-U cartridge and record:

- shell revision and photographed specimen
- width, height, and maximum depth
- label recess dimensions and depth
- side-wing width and groove centers
- lower-front grip field
- screw-center coordinates
- connector mouth and bottom notches
- front/rear half depths and seam position
- top tabs and feet

Use a digital caliper with 0.1 mm resolution or better. Record each value, repeated readings, uncertainty, and any shell-revision variation.

## M2.2 gate

M2.2 may begin a clean front-shell blockout from this package. It may not receive final approval until the physical spot-check is committed and the manifest is revised from `provisional-orthographic-baseline` to `physical-calibrated`.
