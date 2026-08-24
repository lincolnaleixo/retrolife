# M2 SNES anatomy and rebuild plan

## Status

The first procedural M2 cartridge is **rejected as final geometry**.

It remains useful only as an engineering blockout that proved the CC0 source boundary, Godot mesh generation, material slots, pivots, LOD plumbing, and verification approach. It is not the production visual reference and must not be polished incrementally into the final asset.

The production cartridge will be rebuilt from a measured NTSC-U reference through M2.1 to M2.5, issues #74 through #78.

## Non-negotiable source and license boundary

- Production source must remain original CC0 work or use a clearly documented free/open asset compatible with commercial modification and redistribution.
- Paid, subscription-only, account-locked, Editorial, NonCommercial, NoDerivatives, source-unavailable, or unclear-license assets are forbidden.
- No Nintendo logo, game label, legal text, ROM, or console model is included in M2.
- M3 owns real game-label application.

## Reference authority

Use sources in this order:

1. a real North American NTSC-U SNES cartridge measured with calipers;
2. Nintendo design patents [USD343833S](https://patents.google.com/patent/USD343833S/en) and [USD344504S](https://patents.google.com/patent/USD344504S/en) for silhouette and molded-form relationships;
3. high-resolution photographs of authentic front, rear, top, bottom, side, connector, and disassembled shells;
4. the open [MouseBiteLabs Super Nintendo Cartridges](https://github.com/MouseBiteLabs/Super-Nintendo-Cartridges) PCB sources, CC-BY-SA-4.0, for board and connector clearance only;
5. the approved M1 composition, pivot, pose, docking, reverse-motion, and reduced-motion contract.

PAL and Super Famicom shells are not exterior references for this asset.

## Why the alpha failed

The current alpha does not communicate the authentic NTSC-U cartridge strongly enough because:

- the overall body reads as a thick rounded rectangle rather than the flatter molded SNES shell;
- the top silhouette, shoulders, and insertion steps are oversimplified;
- the side wings are too narrow and the grip treatment resembles a ladder of small ribs;
- the label recess uses a heavy raised frame instead of a broad shallow shell-integrated recess;
- the lower front grip channel, bottom feet, and insertion notches are inaccurate;
- the rear uses an oversized generic panel and fine-line grille instead of the authentic broad molded bands and warning area;
- the connector is not a convincing recessed cavity;
- the parting seam, front/rear thickness split, top tabs, underside, and shell taper are not anatomically resolved;
- flat materials amplify the incorrect geometry.

No amount of texture or label artwork can correct these silhouette errors.

# Anatomical checklist

## 1. Overall envelope and silhouette

- Measure width, height, maximum depth, front-half depth, and rear-half depth.
- Match front, rear, top, bottom, and side silhouettes independently.
- Reproduce the stepped top profile and shoulder transitions.
- Reproduce the broad side-wing masses.
- Match outer corner radii and subtle front-to-side taper.
- Preserve the real shell parting seam without making it a thick layered slab.
- Match the lower feet, connector-side notches, and insertion silhouette.
- Keep the root pivot at the measured bottom connector center required by M1.

## 2. Front shell

### Label region

- Broad, shallow, integrated label recess.
- Thin molded rim, not a separate heavy frame.
- Correct vertical position, width, height, corner radius, and inset depth.
- Separate planar label surface with stable 0..1 UVs.
- No game artwork or brand mark in M2.

### Side wings and grip bands

- Correct side-wing width and projection.
- Correct number, pitch, length, depth, and termination of horizontal molded grip bands.
- Bands must read as broad molded steps, not many narrow repeated ribs.
- Side mass must remain legible in focused and docked three-quarter views.

### Lower front

- Correct long horizontal grip channel below the label.
- Correct rounded ends, depth, width, and central interruption where present on the selected shell revision.
- Correct security screw-well positions and diameters.
- Correct lower corner bosses, feet, and insertion notches.
- No invented vents or panel lines.

## 3. Rear shell

- Continue the approved top steps, shoulders, wings, seam, taper, and feet.
- Model broad horizontal molded bands with correct count, pitch, depth, and interruptions.
- Model the warning-label area as a shallow molded region.
- Model a neutral lower badge/plaque region only where the physical mold requires it.
- Do not reproduce Nintendo logos, legal text, serial numbers, or game-specific content.
- Include the top shell tabs/latches visible on an authentic disassembled reference.
- Remove the alpha's generic large inset and artificial grille.

## 4. Bottom and connector cavity

- Model the connector opening as a real recessed cavity.
- Match mouth width, height, depth, inner lips, corner treatment, and outer supports.
- Model bottom insertion notches and anti-misinsert geometry.
- Include a restrained dark interior, PCB edge, and gold contacts where visible.
- Use open PCB dimensions only for internal clearance validation.
- Preserve 1.2 mm PCB thickness and the 30-degree gold-finger chamfer where visible.
- Verify clearance against every M1 docking and reverse-animation keyframe.

## 5. Top and sides

- Correct top-center step, adjacent shoulders, and latch details.
- Correct shell depth profile and front/rear curvature.
- Correct side-wall taper and grip-band wrap.
- Ensure the cartridge does not appear as stacked flat plates in side view.

## 6. Materials

- Neutral light-gray ABS with physically plausible roughness and restrained specular response.
- Subtle mold-grain microtexture at real physical scale.
- Separate dark connector cavity, security screw, PCB, contact, and label-placeholder materials.
- No fake dirt, fingerprints, game wear, branding, or game-specific textures.
- Validate under neutral studio, M1 focused, and M1 docked lighting.

## 7. Label surface and M3 handoff

- Perfectly planar surface separated from the shell.
- Stable UV rectangle from 0,0 to 1,1.
- Explicit top, bottom, left, and right orientation markers in the calibration texture.
- Stable material-slot name and runtime replacement contract.
- Label-safe area remains visible in the bottom dock.

## 8. Pivots and anchors

- Root pivot: bottom connector center.
- Named anchors: center of mass, label center, connector center, browse, focused, dock approach, and docked seat.
- Anchors remain identical across LODs.
- Reverse animation follows the same collision-free physical path.

## 9. LOD and performance

Initial maximum budgets:

- LOD0: 35,000 triangles;
- LOD1: 8,000 triangles;
- 6 material slots;
- 6 draw calls before batching;
- M2 calibration textures no larger than 2048 px per map.

LOD reduction may remove small non-silhouette details, but may not alter:

- outer silhouette;
- label recess or UVs;
- side wings and major grip bands;
- lower front channel;
- rear molded fields;
- connector cavity;
- pivot or dock clearance.

# Ordered correction plan

## M2.1

Lock the real NTSC-U physical reference, caliper measurements, patent-aligned orthographic sheets, normalized landmarks, tolerance classes, and deterministic reference manifest.

## M2.2

Cleanly rebuild the authentic front shell, outer silhouette, top steps, side wings, grip bands, label recess, lower grip channel, screws, feet, and seam.

## M2.3

Build the authentic rear shell, broad molded bands, warning region, top tabs, underside, connector cavity, PCB/contact visibility, and dock clearance.

## M2.4

Finish ABS materials, label UVs, calibration texture, material slots, root pivot, named anchors, LOD0, LOD1, budgets, and deterministic asset validation.

## M2.5

Replace the alpha in Godot, run reference overlays, render all M1 poses, validate motion and reduced motion, pass Linux and Apple Silicon checks, and obtain explicit owner visual approval.

# Production acceptance gate

M2 may close only when:

- the cartridge is immediately recognizable as an authentic NTSC-U SNES cartridge before artwork is applied;
- front, rear, top, bottom, and side overlays satisfy approved tolerances;
- the alpha is absent from the active runtime path;
- the label surface is ready for M3;
- the complete M1 dock and reverse paths are collision-free;
- Linux and Apple Silicon Godot verification pass;
- the final turntable and in-context motion are explicitly approved by the owner.

M3 must not begin against the rejected alpha geometry.
