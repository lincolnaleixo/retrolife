# M2.2 v5 provisional NTSC-U SNES front shell

## Decision

The v1 plate stack, v2 height field, v3 loft-only presentation and visually rejected v4 CAD shell are rejected. The v5 package is rebuilt as a real CadQuery/Open CASCADE boundary-representation solid with drafted boolean features. SVG is no longer the primary geometry or review medium.

The geometry remains provisional. It does not claim physical caliper calibration or final owner approval.

## Generated contract

- Asset ID: `retrolife.snes.na-cartridge.m2.2.front.v5`
- Prior asset ID: `retrolife.snes.na-cartridge.m2.2.front.v4`
- License: `CC0-1.0`
- CAD source: `original-cadquery-opencascade-photo-normalized-brep-rebuild`
- CAD tool: `CadQuery 2.8.0`
- Kernel: `Open CASCADE 7.9`
- Surface model: `cadquery-opencascade-brep-with-continuous-draft-and-shallow-molded-features`
- Envelope: `136.0 x 88.0 x 20.0 mm`
- Front-shell depth: `10.0 mm`
- B-rep volume: `36787.5 mm3`
- B-rep faces: `764`
- B-rep edges: `2272`
- Tessellated triangles: `17934`
- Primary engineering artifact: `snes_ntsc_u_front_shell_v5.step`
- Godot artifact: `snes_ntsc_u_front_shell_v5.obj`
- Review artifacts: deterministic PNG renders from the tessellated CAD solid
- Label surface: separate rounded mesh with stable `0..1` UVs
- Review label artwork: original RetroLife artwork rendered only into the PNG review views
- Root pivot: bottom connector center
- Console, branding, legal text, commercial artwork, ROMs and external mesh data: excluded

## Molded features

- A real side-wall roll is formed by the B-rep section stack.
- The front body is a fused solid, not a stack of visible feature plates.
- The label recess and paired lower grip pockets are shallow drafted boolean features.
- Four recessed side divisions create five broad molded bands per wing.
- Screw wells use small conical countersinks and through openings; metallic screw heads exist only in review renders.
- The back is opened by an internal cavity cut, so the artifact is a front-shell body rather than a solid billet.

## Physical comparison boundary

The comparison record links authentic cartridge photography, the cartridge bottom, the USD343833S design patent and a public physical scan. No vertices, textures or photographs from those references are embedded in the CC0 asset.

## Remaining gates

- Measure one authentic early NTSC-U/C `SNS-006` cartridge with digital calipers.
- Reconcile all provisional B and C dimensions in M2.1.
- Compare the v5 PNG sheet and STEP file against the physical specimen.
- Obtain explicit owner visual approval.
- Keep M2.3 and M3 blocked until those gates close.
