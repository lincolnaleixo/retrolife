# M1 SNES macOS Visual and Bottom-Dock Contract

Status: implemented candidate, pending owner visual approval  
Milestone: M1  
Contract ID: `retrolife.macos.snes.m1.v1`  
Machine-readable source: [`m1-snes-contract.json`](m1-snes-contract.json)

## 1. Purpose

M1 converts the SNES product direction into a deterministic implementation contract.

It is intentionally limited to SNES. It does not authorize production geometry, artwork mapping, or final visual work for another system. M2 through M6 use this contract to create and verify the complete SNES vertical slice. M7 begins only after the signed SNES reference candidate is accepted.

The original owner PDF remains the visual comparison authority. The PDF is not stored in this repository, so the frames in this directory are an implementation candidate for owner review rather than a self-approved claim of visual equivalence.

## 2. Locked decisions

### 2.1 System and physical reference

- Reference system ID: `snes`.
- Reference region: North America.
- Reference physical family: Nintendo `SNS-006` style North American SNES cartridge.
- Contract media family ID: `snes-na-cartridge`.
- Normal browse, selection, details, launch, return, and recovery screens display no console.
- The bottom dock is an abstract RetroLife product surface. It must not resemble or imply a console.
- Final geometry is produced in M2. M1 locks composition, interaction, proportions, poses, and tolerances.

The M2 model may refine measured physical dimensions by at most 2 percent without reopening M1. Changing the region or physical family reopens M1.

### 2.2 Product hierarchy

The selected physical cartridge is the visual hero.

In browse mode:

- one focused cartridge occupies the center;
- one bounded neighbor may appear on each side;
- neighbors remain subordinate through scale, opacity, and perspective;
- title, system name, and short hints are the only required chrome;
- long descriptions and launch actions remain hidden.

In docked mode:

- the committed cartridge remains visible and recognizable;
- the dock covers 27 percent of cartridge height;
- the label title area remains unobstructed;
- only title, system, optional year, primary action, secondary action, and Back hint are shown;
- search, filters, pagination, and long description remain hidden.

## 3. Reference composition

Reference logical viewport: `1600 x 900`.

All positions are normalized to the current safe viewport. M2 and M4 must use normalized endpoints so resizing does not restart or jump an active transition.

### 3.1 Safe area

| Edge | Fraction |
| --- | ---: |
| Left | 6% |
| Right | 6% |
| Top | 5% |
| Bottom | 4.5% |

### 3.2 Vertical zones

| Zone | Start | End |
| --- | ---: | ---: |
| Hero media | 10% | 72% |
| Bottom dock | 76% | 96% |

The minimum reference gap between the hero object and unrelated chrome is 48 logical pixels.

### 3.3 Supported compositions

M1 defines behavior for:

- windowed 16:10 at a minimum logical size of `1100 x 688`;
- fullscreen 16:9 at `1280 x 720` or larger;
- fullscreen 16:10 at `1280 x 800` or larger;
- Retina and external displays with scale factors 1x and 2x;
- aspect ratios from 1.55 through 1.90.

Outside this range, letterboxing or a constrained safe composition is preferred over distorting the cartridge or dock.

## 4. Visual language

### 4.1 Palette

| Token | Value | Use |
| --- | --- | --- |
| Background | `#07080D` | full screen |
| Background lift | `#0D1018` | subtle depth field |
| Surface | `#121620` | dock body |
| Raised surface | `#181D29` | focused action |
| Primary text | `#F6F7FB` | title and selected action |
| Secondary text | `#9CA5B5` | system, year, hints |
| Focus | `#B9A7FF` | focus ring and committed accent |
| Soft focus | `#6F63A8` | subdued focus glow |
| Dock slot | `#242B39` | cartridge slot |
| Dock edge | `#343D50` | physical separation |
| Cartridge shell | `#B7B9BE` | M1 reference silhouette |
| Cartridge shadow | `#7D8088` | reference depth |
| Fallback label A | `#5966B9` | abstract placeholder only |
| Fallback label B | `#D95F9D` | abstract placeholder only |

M2 may calibrate material roughness and light intensity, but the contrast hierarchy must remain unchanged.

### 4.2 Typography

Use the macOS system font through this preference order:

1. SF Pro Display
2. SF Pro Text
3. Helvetica Neue
4. generic sans-serif

No Apple font file is stored or redistributed.

At the reference logical viewport:

- game title: 34 px, weight 600;
- metadata: 17 px, weight 400;
- input hint: 14 px;
- all caps are limited to the system badge and short input hints;
- docked metadata is limited to two lines.

## 5. Cartridge poses

The normalized physical proportion is `1.00 : 0.64 : 0.15` for width, height, and depth. This is a composition ratio for M1, not the final measured mesh.

### 5.1 Browse neighbor left

- center: `(0.245, 0.430)`;
- visual height: `29%` of viewport;
- rotation: `x -4`, `y +14`, `z -1.5` degrees;
- opacity: `34%`;
- blur hint: `1.5 px`.

### 5.2 Browse focused

- center: `(0.500, 0.405)`;
- visual height: `42%` of viewport;
- rotation: `x -5`, `y -9`, `z 0` degrees;
- opacity: `100%`;
- shadow softness: `44 px`.

### 5.3 Browse neighbor right

- center: `(0.755, 0.430)`;
- visual height: `29%` of viewport;
- rotation: `x -4`, `y -14`, `z +1.5` degrees;
- opacity: `34%`;
- blur hint: `1.5 px`.

### 5.4 Dock approach

- center: `(0.500, 0.665)`;
- visual height: `34%`;
- rotation: `x -2`, `y -2`, `z 0` degrees.

### 5.5 Docked

- center: `(0.500, 0.805)`;
- visual height: `30%`;
- rotation: `x -1`, `y 0`, `z 0` degrees;
- occluded height: `27%`.

## 6. Bottom dock

- center: `(0.500, 0.885)`;
- size: `48% x 10.5%` of viewport;
- reference corner radius: `24 px`;
- slot size: `20.5% x 2.3%` of viewport;
- slot center: `(0.500, 0.844)`;
- minimum visible cartridge height after seating: `70%`;
- dock position remains fixed during normal selection animation.

The dock has three visual layers:

1. a matte surface with minimal edge separation;
2. a narrow slot with low-intensity internal light;
3. a soft contact shadow that increases while the cartridge seats.

There is no decorative hardware, controller port, power light, eject button, logo, vent, or other console cue.

## 7. State machine

### 7.1 States

| State | Committed | Dock visible | Browse navigation |
| --- | ---: | ---: | ---: |
| `browseIdle` | no | no | enabled |
| `browseFocused` | no | no | enabled |
| `commitPending` | yes | yes | disabled |
| `docking` | yes | yes | disabled |
| `docked` | yes | yes | disabled |
| `launching` | yes | yes | disabled |
| `launchReturn` | yes | yes | disabled |
| `undocking` | yes until completion | yes | disabled |
| `recoverableError` | yes | yes | disabled |

Initial state: `browseFocused`.

### 7.2 Primary transitions

| From | Event | To | Resulting focus |
| --- | --- | --- | --- |
| `browseIdle` | focus game | `browseFocused` | `browse:game:{gameId}` |
| `browseFocused` | navigate | `browseFocused` | new game key |
| `browseFocused` | Confirm | `commitPending` | none during transition |
| `commitPending` | next frame | `docking` | none |
| `docking` | animation complete | `docked` | `dock:primary` |
| `docking` | Back | `undocking` | reverse current progress |
| `docked` | Back | `undocking` | none during transition |
| `docked` | Launch | `launching` | none |
| `launching` | success | `launchReturn` | none |
| `launchReturn` | settle complete | `docked` | `dock:primary` |
| `launching` | failure | `recoverableError` | `dock:retry` |
| `launching` | cancellation | `docked` | `dock:primary` |
| `recoverableError` | dismiss | `docked` | `dock:primary` |
| `undocking` | animation complete | `browseFocused` | original game key |

### 7.3 Invariants

- Committed game identity does not change from `commitPending` until undocking completes.
- Exactly one semantic focus target exists after every terminal transition.
- A transition emits at most one launch request.
- A catalog refresh may not replace the committed game while docking or docked.
- Media becoming available may update the label surface without changing identity or animation progress.
- Back during docking reverses from current progress. It does not jump to either endpoint.
- A viewport change recalculates normalized endpoints and preserves animation progress.
- Repeated Confirm during docking is ignored.
- Browse navigation is disabled while docked.

## 8. Motion contract

### 8.1 Focus change

Duration: `190 ms`  
Easing: cubic out  
Input coalescing window: `65 ms`

A focus change may translate and rotate the incoming cartridge, but it may not delay semantic focus or block additional bounded navigation.

### 8.2 Confirm and docking

Total duration: `620 ms`.

| Time | Motion |
| ---: | --- |
| 0 ms | focused browse pose |
| 0 to 40 ms | commit identity and lock conflicting input |
| 70 ms | rise by 1.8% of viewport height, scale 1.015 |
| 250 ms | travel toward dock approach, scale 0.91 |
| 480 ms | enter slot with 7 px reference overshoot |
| 620 ms | settle at docked pose, overshoot 0 |

Easing:

- main travel: quintic in-out;
- seating: limited back-out;
- no elastic bounce;
- no camera shake;
- no glow flash.

The contact shadow tightens during the final 140 ms. The dock stays still.

### 8.3 Undocking

Total duration: `540 ms`.

Undocking follows the inverse spatial path with quintic in-out easing. It restores the original browse game, filters, scroll position, and semantic focus only after the cartridge reaches the focused browse pose.

Back pressed during docking starts this reverse behavior from current normalized progress.

### 8.4 Launch return

The external launch path preserves the committed cartridge.

After the frontend becomes active:

- restore the docked composition without replaying the full docking animation;
- use a `240 ms` settle;
- return focus to `dock:primary`;
- show failure or cancellation status without moving the cartridge out of the dock.

### 8.5 Reduced motion

Duration: `120 ms`.

Reduced motion:

- performs no travel path;
- performs no rotation;
- performs no scale pulse;
- crossfades browse chrome to docked chrome;
- places the cartridge directly in the docked pose;
- preserves the same committed identity, focus, launch, error, and Back semantics.

Reduced motion is an equivalent product state, not a simplified navigation branch.

## 9. Input and focus contract

### 9.1 Semantic keys

- browse game: `browse:game:{gameId}`;
- dock primary action: `dock:primary`;
- dock secondary action: `dock:secondary`;
- dock Back action: `dock:back`;
- retry after failure: `dock:retry`.

### 9.2 Conflict handling

- Confirm during docking: ignored.
- Back during docking: reverse current progress.
- Navigation during docked state: disabled.
- Filter or search completion during a transition: update deferred until browse is restored, unless it does not affect committed identity.
- Missing label becoming available: update in place without restarting motion.
- Window resize: preserve state and normalized progress.
- Duplicate launch request: rejected.

## 10. Golden frames

[`m1-snes-golden-frames.svg`](m1-snes-golden-frames.svg) contains the six required static states:

1. browse;
2. focused;
3. docking;
4. docked;
5. launch return;
6. undocking.

These frames are layout and hierarchy references. The cartridge silhouette is deliberately simplified because production geometry belongs to M2.

## 11. Motion storyboard

[`m1-snes-motion-storyboard.svg`](m1-snes-motion-storyboard.svg) records:

- eight normal-motion panels from focused browse through final seating;
- the reverse path and cancellation rule;
- three reduced-motion panels;
- timings, normalized positions, scale, and focus behavior.

M4 must preserve these semantics even if final mesh dimensions require minor pose calibration within the M2 tolerance.

## 12. M2 handoff

M2 may proceed without inventing unresolved behavior. The following are locked:

- North American SNES reference family;
- no console in normal flow;
- normalized camera composition and poses;
- fixed bottom dock and 27 percent occlusion;
- state names and transition semantics;
- normal and reduced-motion behavior;
- animation durations and easing families;
- semantic focus restoration;
- launch-return behavior.

M2 may calibrate only:

- mesh dimensions within 2 percent;
- material roughness and micro-normal detail;
- light intensity within 10 percent while preserving contrast;
- label safe inset after measured geometry exists.

The following require an M1 revision:

- changing cartridge region or family;
- showing a console;
- redesigning or relocating the dock;
- changing commit or cancellation semantics;
- changing reduced-motion state equivalence.

## 13. Verification

Run:

```bash
python3 scripts/verify-m1-snes-contract.py
```

Success marker:

```text
RETROLIFE_M1_SNES_CONTRACT_OK
```

The validator checks the machine-readable contract, all required states and transitions, timing bounds, safe normalized positions, required golden-frame panels, motion storyboard metadata, the no-console rule, and the SNES-only production gate.

## 14. Approval boundary

Implementation and deterministic verification can complete in source control.

M1 remains provisional until the owner reviews the static frames and motion storyboard and explicitly accepts the visual direction.
