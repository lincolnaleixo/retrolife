# M2.2 provisional NTSC-U SNES front shell

## Status

This package implements the clean M2.2 front-shell blockout. It is generated from the committed M2.1 provisional reference package and does not reuse the rejected alpha geometry.

It is not final dimensional approval. M2.1 physical calibration and explicit owner approval remain required before the geometry can be finalized.

## Generated contract

- Asset ID: `retrolife.snes.na-cartridge.m2.2.front.v1`
- License: `CC0-1.0`
- Source: `original-parametric-clean-rebuild`
- Provisional envelope: `136 x 88 x 20 mm`
- Front-half depth: `10.4 mm`
- Generated triangles: `11264`
- Root pivot: bottom connector center
- Side grip grooves: five per wing
- Label surface: separate planar mesh with stable `0..1` UVs
- Console, branding, legal text, game artwork, ROMs and third-party meshes: excluded

## Godot interface

`SnesNaCartridgeFrontM2_2.tscn` exposes five mesh nodes and the named `DockPivot`, `CenterOfMass`, `LabelAnchor`, `ConnectorAnchor`, `BrowseFocusedAnchor` and `DockApproachAnchor` markers.

The scene is an independent M2.2 source asset. M2.5 owns replacement of the active alpha runtime scene.

## Remaining gates

- Measure one authentic early NTSC-U/C `SNS-006` cartridge with digital calipers.
- Reconcile the M2.1 B and C confidence dimensions.
- Rerun generation, overlays and platform smoke tests after calibration.
- Obtain explicit owner approval of the corrected front clay and M1 poses.
- Keep M3 blocked until the complete M2 gate closes.
