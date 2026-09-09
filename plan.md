# RetroLife plan

Last reviewed: 2026-09-09. Product focus: SNES on macOS, with a clean, premium cartridge-first library.

This is the only roadmap. The owner's scope for this revision is **plan.md only**: no application code, assets, dependencies, changelog, version fields, tags, releases, or other repository files are changed. The normal changelog and verification rules apply to subsequent implementation work.

## Product outcome

By the end of these ten milestones, a user can install RetroLife on an Apple Silicon Mac, import their own SNES ROMs, browse a beautiful collection of real 3D cartridges, launch a game inside the app, save and restore its exact state, and install a newer GitHub release without leaving the application or losing their library and saves.

The interface must feel like a carefully designed collection, not an emulator settings dashboard, a grid of text buttons, or a decorative 3D demo disconnected from playable games. Visual quality and dependable everyday use are release requirements, not optional finishing work.

**Platform contract:** macOS 13+ on Apple Silicon remains the supported target. Intel Mac support is not implied. Linux remains useful for development/CI, but Linux distribution, Steam Deck, Windows, mobile, and additional consoles are outside this cycle. SNES regional variants are still SNES; prioritize the existing North American shell without incorrectly presenting every ROM as a North American edition.

**Architecture contract:** retain Rust, Godot, the GDExtension bridge, the owned libretro worker, and the pinned bundled SNES core. Do not migrate to Electron, Tauri, a web frontend, or an external emulator launcher. No account, server, runtime core download, or network connection is required to import, browse, play, or restore local progress.

## Baseline: implemented, published, and still unverified

Source reviewed at `46f2763c1411d051f536efa8686d55760c15db0d`. Release information was also checked independently of the older roadmap text.

| Area | Observed baseline | Gap to close |
| --- | --- | --- |
| macOS distribution | GitHub has `v0.1.0-beta.2`, published 2026-09-09, with DMG, ZIP, checksums and corresponding-source archives. Its notes report signed/notarized/stapled packaging and Gatekeeper checks. Application commit: `a211f4c8b7908df2182a1c98f5dee41902500ab6`; beta.2 changes packaging, not the beta.1 application binary. | Hands-on keyboard/gamepad gameplay, audible sound, sustained sessions and user-game save restoration remain explicitly pending in those notes. Completed `v0.1.0` is not established. |
| Emulation | Rust owns the native core session and bounded transports; Godot presents video/audio and maps input. Pause/resume and save-aware shutdown exist. | Complete native acceptance and later add state serialization without violating the worker ownership boundary. |
| ROM library | Managed `.sfc`/`.smc` copies, raw-content SHA-256 identities, duplicate detection, import journal, atomic metadata replacement and integrity checks exist. `library.json` currently has schema version 1; entries contain identity, title and relative path. | Better batch/folder/archive workflows, richer metadata, migration, repair and nonblocking progress. Do not rewrite the working storage foundation. |
| Frontend | `main.gd` builds text-based cards and a text-heavy details overlay. It rebuilds cards during refresh and requests the first page with `PAGE_LIMIT = 500`. | Real cartridge rendering, reusable components, deliberate layout, scalable navigation, and access to the complete collection rather than only the first 500 results. |
| Progress | Local battery-backed saves and write-failure recovery are implemented. | Battery saves are not save states. Slots, serialization, thumbnails, quick save/load and reliable resume are not delivered. |
| Cartridge collection | External `snes-ntsc-u` asset v0.1.0 has a release manifest and GLB. The manifest reports 22 meshes, 9 materials, 4 embedded images, no external images, and a Godot 4.7.2 headless import check. The GLB is about 25 MB; the full source package is about 49 MB. | Application integration, actual material/surface mapping, visual verification, runtime memory measurements, and per-game labels. A headless asset import is not proof of a beautiful in-app render. |
| Updates | `.github/workflows/release.yml` validates and archives source on version tags. | There is no delivered in-app update installation flow or appcast publication pipeline. A source-validation workflow is not an updater. |

The previous plan's statement that no signed release exists and its Keychain blocker are historical, not the current release status. The beta.2 release notes supersede those claims. This planning review did not run the Mac binary or independently repeat signing, notarization, audio or controller tests. README, CHANGELOG and release documentation still contain older status wording; reconcile them during v0.1.0 implementation, not in this plan-only commit.

### Preserve completed work and its evidence

- [x] Preserve previous work and the historical repository outside the replacement public source boundary.
- [x] Establish the fresh public Rust/Godot baseline, English development rules, licensing, notices and single roadmap.
- [x] Implement managed imports, owned emulation sessions, local battery persistence and recovery tests.
- [x] Establish pinned core builds, redistributable generated test content, hosted CI, publication auditing and corresponding-source packaging.
- [x] Publish the audited source repository.
- [x] Record the published signed testing prerelease and distinguish its packaging evidence from gameplay acceptance.
- [ ] Complete hands-on acceptance and publish the completed v0.1.0 milestone.

The earlier verification record reports formatting, Clippy, 32 Rust unit tests, real bsnes-jg video and battery-save round-trip/retry checks, and Godot import/library/input smokes on Linux and native Apple Silicon. It also records clean extension registration, arm64 bridge/core builds, packaged startup, a targeted private-path scan, hosted CI, and 32 offline Rust tests after extracting corresponding-source bundles. Preserve those results as historical evidence, not as tests rerun by this planning edit. Regenerate source/artifact bundles from each actual release commit.

## Design specification for the whole cycle

### Collection layout

Use a quiet dark graphite canvas, warm neutral surfaces, off-white text, and one restrained lavender accent inspired by SNES controls. Let the cartridge and its artwork provide most of the color. No neon rainbow outlines, persistent technical status text, oversized empty panels, fake CRT room, or ornamental animation competing with the games.

Use one shared theme with an 8-point spacing rhythm, consistent 24-32 px content gutters, a readable redistributable sans-serif font, clear title/body/caption hierarchy, restrained corners, and consistent focus/hover/pressed states. Keep ordinary text comfortably readable at the supported minimum window size. Evaluate actual contrast, not color names alone.

The desktop composition is:

```text
RetroLife                 Search your games       Import ROMs   Settings

Library / Favorites / Recent

[ Large selected 3D cartridge ]  Game title
[ Soft neutral display stage ]  Region, year, recent activity
[ Rotate / reset view        ]  Play or Resume     Details

[ cartridge ] [ cartridge ] [ SELECTED ] [ cartridge ] [ cartridge ]

Collection count / sort / optional compact grid / contextual input hints
```

This is a layout specification, not an implementation or a screenshot. Adapt it rather than compressing it when the window narrows. At 1280x720, the selected cartridge, title and primary action must be visible without scrolling. At smaller supported windows, move supporting content below the hero. Define and test a minimum logical window size of 1024x640; unsupported smaller sizes must not silently clip controls.

Default browsing is a cartridge-first 3D shelf with a clearly selected game. A compact grid/list is a secondary efficiency and accessibility view. Cached renders are appropriate for the compact grid and distant items, but a flat thumbnail grid must not be presented as completion of the primary 3D experience.

### Cartridge appearance and interaction

Use the actual detailed `snes-ntsc-u` GLB, not a rectangular box with a cover image pasted on it. Preserve its shell silhouette, thickness, curved roof, folded label, rounded grips and lower recesses. Frame it in a consistent three-quarter view with a readable label, natural plastic roughness, soft lighting, a subtle contact shadow and enough margin to avoid clipping during rotation.

The GLB convention is meters, X width, Y up, positive Z front, with a pivot near the bottom connector center. Put it under a presentation pivot for inspection; do not destructively recenter the source model. Apply uniform scale. Inspect actual mesh names, material slots, UVs and texture color spaces before writing a surface mapping; counts alone do not identify the label surfaces.

The front and folded top label must follow the actual geometry. Do not stretch a box cover over the shell, mirror a label, invent missing top artwork, or make a floating flat decal intersect the curved roof. Where a supplied image does not cover a surface, provide a deliberate neutral treatment or a separately edited top label. Rear labels can remain neutral when rights-cleared content is unavailable.

Hover/focus can produce a subtle lift and limited tilt. Selecting a game should settle quickly, with approximately 160-220 ms transitions as an initial design target. Inspection supports pointer drag, trackpad-friendly zoom and reset view. No forced spinning, inertia that makes navigation difficult, or long launch animation. Reduced motion disables decorative movement without removing game selection or access to 3D inspection.

Use one active showcase renderer with a bounded number of visible cartridge instances and shared shell resources. Give each game's changing label materials their own safe instance so selecting one title cannot replace another title's label. Stop unnecessary 3D rendering during gameplay, when hidden or minimized, and after a static presentation has settled where supported.

### Screen and evidence requirements

The same design language must cover the empty library, first import, normal collection, search results, missing artwork, game details, importing/error states, pause menu, save-state picker, settings and update prompt. Do not polish only the happy-path hero screenshot.

Each UI milestone requires screenshots and a short interaction capture from the actual Godot application on Mac, plus keyboard/gamepad focus checks. Public evidence uses original or redistributable fixtures; private game/artwork testing stays outside public source and artifacts. Headless smokes cannot approve lighting, label quality, smoothness or audible playback.

## Data, asset and release boundaries

**Stable identity and migration.** Keep the raw imported-byte hash as the existing storage/save identity. Filename cleanup, catalog matches, region corrections, favorites, label replacements and collection grouping must not change it. If header-aware or canonical hashes are added for matching, store them separately with their derivation version. Never silently merge different ROM revisions, translations, hacks or headered/unheadered files. Any migration from `library.json` v1 needs a backup, atomic commit, interruption recovery and a safe refusal of unsupported future schemas. Introduce that mechanism with the first persisted schema change, not after users already need it.

**Application data.** Keep the established `io.github.lincolnaleixo.retrolife` application-data identity and user data outside the replaceable `.app`. Add namespaced metadata, labels, states, thumbnails and caches without relocating existing ROMs/SRAM casually. Cache cleanup must never delete ROMs or progress. Removing a game defaults to retaining its saves; deleting managed copies or saves is explicit and cannot delete the user's original source file.

**Versioned models.** The initial integration target is `snes-ntsc-u` v0.1.0 from the external collection, inspected at collection commit `a5a184ff1b463b540c56a081e1da625f70067d7a`. Pin the exact manifest/release and archive/file SHA-256 values; never consume floating `main` or `latest` at runtime. Download and verify source packages during controlled build preparation, package only the required runtime model/resources/notices, and keep Blender sources and unrelated example packages out of the app. A normal first launch must not require a 49 MB model download. Future asset updates are reviewed dependencies, not silent executable/content replacement.

**Asset rights and scope.** The collection currently declares CC BY-NC-ND 4.0 for original contributions, not the app's AGPL license. Record attribution and the owner's distribution/adaptation permission where the integration requires it. Do not assume that the owner's model permission grants rights to third-party labels. The `snes-super-mario-world` example is a useful private visual reference, not a default redistributable game-art pack. User-supplied labels remain local. A missing, unapproved or broken model/label must have a neutral fallback and must never prevent launching an otherwise usable game. This task does not change the asset repository or its license.

**Untrusted imports.** ROMs, ZIP entries, metadata and images are untrusted input. Use bounded reads, staging, validated paths and decoded-size limits; do not execute content or allow imports to write arbitrary filesystem paths. Do not load user-provided Godot scripts, scenes or resource packs as artwork. Keep network enrichment optional and independent of playability.

**Early risk checks.** During v0.2.0, prove a real pinned-core serialize/restore round trip in a development harness and prove that a pinned Sparkle 2 build can be loaded, initialized and signed with the exported Godot app. Also inspect the model's label surfaces and permissions. These are bounded dependency checks, not claims that save-state UX or application updates are already shipped. Resolve failed checks before their dependent milestones, rather than discovering them in v0.7.0 or v0.9.0.

## The next ten versions

There are exactly ten product milestones below: **v0.1.0 through v0.10.0**. The existing v0.1.0-beta.2 is a testing prerelease of the still-open first milestone, not a completed milestone or an extra version in this count. Intermediate beta/RC builds and necessary patch fixes do not add roadmap milestones. All dates remain evidence-based; no release is complete because its heading exists.

| # | Target | User-visible outcome | Main dependency |
| --- | --- | --- | --- |
| 1 | v0.1.0 | Accepted, signed SNES application on Mac | Existing beta plus native acceptance |
| 2 | v0.2.0 | Clean redesigned library shell and coherent screens | Accepted gameplay/import baseline |
| 3 | v0.3.0 | Beautiful interactive real SNES cartridge | Design system, asset/rights validation |
| 4 | v0.4.0 | Complete cartridge-first game selection | Real cartridge component |
| 5 | v0.5.0 | Smooth batch, folder and ZIP ROM imports | Stable library identity/migration |
| 6 | v0.6.0 | Correct titles, editions and per-game labels | Robust imports and 3D surface mapping |
| 7 | v0.7.0 | Save/load slots, quick save and resume | Serialization proof and stable ROM identity |
| 8 | v0.8.0 | Daily-use Mac polish and updater-capable build | Reliable saves; early Sparkle proof |
| 9 | v0.9.0 | Full GitHub-backed in-app update experience | Signed updater-capable v0.8.0 |
| 10 | v0.10.0 | Integrated, visually accepted SNES Mac release | All preceding capabilities verified together |

### 1. v0.1.0: finish the accepted Mac baseline

**Status:** in progress. Much of the implementation and signed testing packaging already exists; manual product acceptance is open. Evidence work remains linked to [issue #1](https://github.com/lincolnaleixo/retrolife/issues/1).

**Deliverables**

- [ ] Install the published candidate through its real DMG/Applications flow on a clean standard-user Mac account; do not rely on a development checkout or preexisting Godot data.
- [ ] Exercise first import, game launch, video, audible audio, all SNES keyboard controls, a physical gamepad, pause/resume, exit, restart and battery-save restoration.
- [ ] Check cancellation, unsupported/corrupt input, missing managed files, disk/permission save failures and retry. Preserve the existing policy of not discarding the active session after a failed save.
- [ ] Run a sustained session and repeat library/game transitions; record machine, macOS, core revision and what was actually tested. Include ordinary games and representative supported enhancement-chip cases using lawfully supplied private content or redistributable tests; do not claim universal compatibility.
- [ ] Reconcile README, changelog and release instructions with published beta evidence and the real remaining blockers. Verify all displayed/build versions come from a consistent release definition before publishing final artifacts.
- [ ] Rebuild/audit final source and dependency bundles from the exact release commit, sign nested native code and the app, notarize/staple the final distributable, and verify the downloaded artifact with Gatekeeper.
- [ ] Publish the completed v0.1.0 only after acceptance. Keep testing builds explicitly labeled; do not mutate existing beta tags or artifacts to simulate completion.

**Acceptance:** a downloaded app imports and runs a game without developer tools, produces audible sound, accepts physical input and restores its battery save after a full app restart. Record at least one 30-minute native session and a save-write failure/retry check. Signing results, downloaded-artifact checks and source provenance must refer to the same final build. No advanced 3D or save-state claim is required yet.

**Primary areas:** `frontend/godot-ui/scripts/launch_integration.gd`, `frontend/godot-bridge`, `crates/retrolife-emulation`, release/build scripts, `.github/workflows`, and release documentation.

### 2. v0.2.0: clean frontend foundation

**Status:** planned. Start the visual work immediately after the baseline instead of leaving all design to v0.10.0. Link design evidence to [issue #2](https://github.com/lincolnaleixo/retrolife/issues/2).

**Deliverables**

- [ ] Turn the visual specification above into shared theme tokens and reusable library, toolbar, navigation, detail, dialog, status and action components. Break up the monolithic shell without moving domain logic into Godot.
- [ ] Implement the responsive composition, comfortable spacing and typography. Remove persistent backend/debug/catalog-source labels from normal browsing; put diagnostics in a dedicated surface.
- [ ] Scope the visible product to the user's imported SNES library. Hide multi-console controls and demo catalog entries from normal use without destroying useful test contracts.
- [ ] Design and connect real empty/loading/error/search/import/detail states. Keep unavailable future actions hidden or explicitly unavailable; do not ship clickable mock Play, Resume or Update buttons.
- [ ] Establish consistent pointer, keyboard and gamepad focus, macOS search shortcuts, modal focus return, reduced motion and adequate contrast. Validate actual platform accessibility support and document any gaps rather than claiming full screen-reader support from keyboard tests alone.
- [ ] Introduce migration/backup handling before any persisted UI/library schema change; preserve v1 libraries and SRAM.
- [ ] Complete the early serialization, Sparkle/export and cartridge-surface/permission checks. Record the exact pinned dependency versions, results and unresolved blockers in this plan or linked bounded evidence.

**Acceptance:** the real app is coherent at 1024x640, 1280x720 and a Retina desktop size; no clipped primary controls, inconsistent section alignment or unexplained empty panels. Import/play/back still works from the redesigned shell. Capture empty, populated, details and error screens plus one keyboard/gamepad navigation recording. This milestone approves the shell, not the final 3D integration.

**Primary areas:** `frontend/godot-ui/scenes`, `frontend/godot-ui/scripts/main.gd`, `project.godot`, UI theme/resources, `frontend/godot-bridge`, and persistence contracts where necessary.

### 3. v0.3.0: real SNES cartridge showcase

**Status:** planned. This is the first visually complete cartridge vertical slice, using the actual external asset.

**Deliverables**

- [ ] Resolve and verify the pinned neutral `snes-ntsc-u` package and required notices. Produce a repeatable build-time asset import with explicit failure messages and no private dependency.
- [ ] Inspect the GLB in the pinned Godot version and map actual shell/front/folded-top/rear surfaces in a versioned adapter. Preserve imported source resources and use presentation/material overrides rather than fragile mesh-index guesses.
- [ ] Implement a reusable cartridge view with stable camera framing, presentation pivot, soft lights, neutral environment, contact shadow and realistic plastic/label response.
- [ ] Support safe per-game label textures, including a basic local image override and an original title-based neutral fallback. Correct aspect ratio, crop, orientation, edge behavior, texture filtering and material color-space handling.
- [ ] Add direct rotation, sensible zoom limits, reset view, focus/hover feedback and reduced-motion behavior. Inspection must not accidentally launch or deselect a game.
- [ ] Handle absent/corrupt resources, unsupported mappings and missing labels without a blank screen. Isolate each game's label material while sharing the shell geometry and unchanged textures.
- [ ] Package the model for offline use. Measure actual geometry/texture residency and initial load time; do not assume a 25 MB file implies 25 MB of GPU/RAM usage.

**Acceptance:** show the real model inside the Mac app in hero, front, top, rear and close label views. No distorted shell, clipped edges, mirrored/stretched label, z-fighting, floating folded label or unintended transparency. Two different locally labeled games can be inspected successively without label bleed. A neutral-label game still looks intentional and can launch. Compare against the asset's reference renders and inspect the exported build, not only the editor.

**Primary areas:** new cartridge presentation resources under `frontend/godot-ui`, an asset manifest/build adapter, existing build/export scripts, and asset notices. Geometry changes, if needed, belong to a separately versioned upstream model change, not an untracked copy.

### 4. v0.4.0: cartridge-first game selection

**Status:** planned. Make the beautiful model the actual way to choose games, not an isolated viewer.

**Deliverables**

- [ ] Implement the default 3D shelf: the selected cartridge and a small bounded set of neighbors are actual model instances in a shared scene; start with at most five visible live instances and profile before increasing it.
- [ ] Make selection obvious and consistent. Single click selects; double click, the primary Play action, Enter or the mapped gamepad confirm launches. Keep Inspect/Details distinct from Play; do not force a long animation before starting.
- [ ] Connect the hero's title, edition, label and actions to the selected imported content identity. Never launch by grid index, display title or a stale async asset response.
- [ ] Add persistent favorites and real recently played history, sorting and search. Preserve selection, scroll position, filter and focus when leaving a game or closing details.
- [ ] Remove the first-500-results ceiling with genuine pagination/virtualization. Reuse views and cached resources rather than rebuilding the complete scene for every keystroke.
- [ ] Add the optional compact grid/list with generated/cached cartridge previews. Invalidate preview caches when label, model version or presentation settings change; retain interactive 3D for the selected game.
- [ ] Separate browse navigation, inspection gestures, dialogs and gameplay input contexts. Test trackpad scrolling, repeated key/gamepad input and controller disconnection during selection.
- [ ] Stop or reduce hidden showcase rendering during gameplay/minimization. Cancel stale loads and enforce a bounded model/texture/thumbnail cache.

**Acceptance:** browse, search, favorite, inspect, launch and return using mouse/trackpad, keyboard and gamepad. Rapidly change selection while assets load and prove that title, label and launched ROM always agree. Reach entries beyond item 500 in a 1,000-entry synthetic library. The default view remains smooth and visibly 3D; the compact view is optional, not a substitute for this milestone.

**Primary areas:** library scenes/components, `main.gd`, `catalog_client.gd`, `frontend/godot-bridge`, `crates/retrolife-core`, and `crates/retrolife-library`.

### 5. v0.5.0: robust ROM import and library management

**Status:** planned. Extend the existing managed-copy and journal contracts.

**Deliverables**

- [ ] Support drag-and-drop, multi-file selection, folder import with an explicit recursive option, and local ZIP archives containing `.sfc`/`.smc` files. Nested archives, RAR and 7z are not required in this cycle.
- [ ] Add a nonblocking queue with discovery/import progress, cancellation, bounded work, per-item results and clear imported/duplicate/skipped/failed totals. One bad file must not discard successfully imported items.
- [ ] Preserve original files and existing raw SHA-256 identities. Identical content under another filename should resolve to the existing entry; different revisions remain separate even if titles match.
- [ ] Validate extensions, size and safe header plausibility without treating a filename or header as proof of authenticity. Keep unfamiliar homebrew/hacks distinguishable from clearly invalid files rather than rejecting them solely for missing catalog metadata.
- [ ] Enforce archive traversal/symlink protection, entry-count and total-uncompressed-size limits, compression-ratio/decoded-size protections, and safe handling of encrypted, truncated and mixed-content archives. Never extract outside staging or scan a whole drive without user selection.
- [ ] Make cancellation/crash recovery and disk-full handling transactional per item. Preserve the current journal guarantees and serialize conflicting metadata mutations instead of letting multiple import workers corrupt the index.
- [ ] Add repair/reimport for missing or corrupt managed copies, storage usage, and explicit remove-from-library/delete-managed-copy actions with separate save retention. Do not introduce a mandatory external-folder reference mode or change the application-data root.
- [ ] Handle macOS picker permissions, inaccessible folders, Unicode filenames and files that change during import with understandable recovery actions.

**Acceptance:** import a mixed test folder and ZIP with valid images, duplicates, corrupt input, unsupported files and multiple ROM entries. Cancellation, restart and simulated write failure leave a consistent library; originals remain byte-identical. Reimport existing beta/v0.1 content without losing SRAM or metadata. UI navigation remains responsive throughout import. No rejected archive entry can write outside the staging area.

**Primary areas:** `crates/retrolife-library`, `frontend/godot-bridge`, import/library-management UI and existing local-library smokes.

### 6. v0.6.0: accurate game identity, metadata and labels

**Status:** planned. Make a large imported collection attractive and understandable, without guessing artwork or changing save identities.

**Deliverables**

- [ ] Separate ROM identity, edition/revision, catalog identity, display metadata and cartridge presentation. A title correction must never rename content IDs or orphan saves.
- [ ] Improve identification using ROM headers, normalized filename hints and a rights-reviewed, versioned local checksum catalog or user-supplied compatible DAT data. Treat unknown matches as unknown. Metadata enrichment is never required to launch a game.
- [ ] Where needed, derive a separate copier-header-aware matching hash with a documented algorithm. Preserve original imported bytes and IDs; do not retroactively strip headers or merge entries without explicit, tested migration.
- [ ] Provide user-editable title, region, year and useful optional metadata, plus provenance/confidence and a way to undo an automatic match. Group variants for browsing without collapsing their independent ROMs and progress.
- [ ] Complete a local label editor/importer with preview, crop/fit, orientation and separate front/top handling. Preserve manual choices on reimport, catalog refresh and app update.
- [ ] Prefer an explicit user override, then a verified matching label, then an original neutral title label. Never assign a random commercial game's label based on a loose filename match.
- [ ] Represent shell region honestly. Use the North American asset for appropriate editions; use a clearly neutral/generic presentation for unmatched regional shells rather than claiming an accurate PAL/Japanese reconstruction that does not exist.
- [ ] Cache validated label derivatives and thumbnails by content/version; bound image dimensions and memory usage. Keep artwork sources and rights separate from application code. Online scraping or a provider account is not a dependency of this release.

**Acceptance:** test known and unknown titles, regional variants, headered/unheadered images, translations, revisions and manual corrections. Repeated import preserves overrides and existing SRAM. The shelf shows different games with correctly fitted labels; missing artwork remains visually polished. A metadata mistake is editable and cannot make Play target a different ROM.

**Primary areas:** `crates/retrolife-core`, `crates/retrolife-library`, bridge contracts, game-details/label-editing UI and cartridge texture/cache logic.

### 7. v0.7.0: save states, quick save/load and resume

**Status:** planned. Extend [issue #3](https://github.com/lincolnaleixo/retrolife/issues/3) with local state evidence; cloud synchronization remains deferred.

**Deliverables**

- [ ] Expose serialization capability and implement `retro_serialize_size`, `retro_serialize` and `retro_unserialize` through the owned emulation worker. Execute requests at a safe frame boundary, never concurrently with core execution or from the Godot UI thread.
- [ ] Use bounded, acknowledged commands with request/session identities. UI success means serialization/restoration and the required persistence operation actually completed, not that a command entered a queue.
- [ ] Define a versioned state envelope with raw ROM hash, core identifier and pinned build/revision, compatibility-affecting options, format version, timestamp, payload length/checksum and screenshot reference. App version alone is not a compatibility key.
- [ ] Deliver ten manual slots per ROM, one separate quick-save slot, and a three-generation automatic-resume history. Show screenshot, time and slot status in a clean picker; provide buttons, menu actions, configurable shortcuts and gamepad navigation.
- [ ] Capture thumbnail and serialized state from the same acknowledged frame boundary. Avoid showing a screenshot from another frame, another game or a failed write.
- [ ] Add automatic state capture on orderly exit/game switch and before an accepted update restart. Offer Resume only when a compatible state exists; keep New Game/normal battery-save boot explicit and non-destructive. Do not promise recovery of unsaved progress after a hard crash or core hang.
- [ ] Write states atomically, retain previous valid slots, reject corrupt/oversized/wrong-ROM/incompatible-core states before applying them, and show recoverable errors. Preserve existing battery-save files independently of state files.
- [ ] Define SRAM behavior when restoring a state that contains older cartridge memory. Keep a recovery snapshot and SRAM backup before a destructive load; expose a last-load recovery action. Do not immediately overwrite the durable battery file on failed restoration. If rollback cannot safely restore the session, stop with a visible recovery path without committing corrupted progress.
- [ ] Keep the pinned core revision through this cycle unless a necessary fix is reviewed. A core change requires explicit compatibility tests and a safe migration/incompatibility message, not a blanket promise that all older states will load.

**Acceptance:** save at a recognizable point, continue, restore the exact point, quit the app, reopen and restore again. Verify all slot types and thumbnails, multiple games, battery persistence, a full disk, interrupted writes, bad checksums, wrong ROM/core and failed unserialization. Test core load/state operations under pause, rapid requests and session changes. Use real-core tests and native interaction, not only mocked byte round trips.

**Primary areas:** `crates/retrolife-emulation` core bindings/worker/persistence, `frontend/godot-bridge`, `launch_integration.gd`, pause/state-picker UI and save compatibility tests.

### 8. v0.8.0: everyday Mac polish and updater foundation

**Status:** planned. This must be an updater-capable signed release so the next release can genuinely arrive through the installed app.

**Deliverables**

- [ ] Finish fullscreen/windowed transitions, remembered window/UI settings, Retina scaling, native file/menu behavior and consistent shortcuts without stealing input while typing or using a modal.
- [ ] Improve controller mapping, two-player input where supported, hot-plug/reconnect and actionable controller feedback. Test at least two documented physical controller families rather than claiming support from synthetic input alone.
- [ ] Handle focus loss, sleep/wake and audio-device changes. Avoid stale held buttons, runaway frame catch-up and stuck/duplicated audio after resuming.
- [ ] Keep pause, states, library return and errors visually consistent. Eliminate unnecessary collection rendering during gameplay and verify clean session stop before closing the app.
- [ ] Integrate a pinned, security-reviewed Sparkle 2 framework through a minimal macOS-native adapter at the frontend/platform boundary. Initialize and call its UI-facing lifecycle on the appropriate main thread; keep Cocoa/platform code out of Rust domain/emulation crates.
- [ ] Ship the actual updater engine, trusted feed URL, embedded public verification key, increasing build number and a working manual Check for Updates action. A placeholder button or only a release-page link does not satisfy the foundation.
- [ ] Prove framework/helper packaging, rpaths, preserved symlinks, required entitlements and signing/notarization with the Godot-exported bundle. Do not weaken production library validation or run public PR code on the signing machine.
- [ ] Test installation between two distinct signed staging builds on an isolated test feed. Publish the production updater-capable v0.8.0 with the validated configuration; the production feed may report no newer release until v0.9.0 is approved.

**Acceptance:** run a one-hour native session with pause/load, fullscreen changes, controller disconnect/reconnect and sleep/wake; demonstrate no progress loss or growing background rendering cost. The downloaded v0.8.0 passes Gatekeeper, launches offline, and can check the production feed. A staging old-build-to-new-build install verifies that the native adapter is not merely able to display an update dialog.

**Primary areas:** Godot shell/gameplay/input, bridge/platform adapter, macOS export/sign scripts, bundle metadata and updater integration tests.

### 9. v0.9.0: complete GitHub-backed in-app updates

**Status:** planned. Finish user-facing discovery, trusted publication and real update installation using the v0.8.0 foundation.

**Deliverables**

- [ ] Use GitHub Releases for versioned application/source artifacts and generate a trusted HTTPS Sparkle appcast from reviewed, complete releases, hosted through GitHub Pages or an equivalently owner-controlled static endpoint. Do not interpret a random new tag, draft release or source-only archive as an installable application.
- [ ] Extend the release process so approved source/build checks, native packaging/signing/notarization, checksums, notices, corresponding source and update metadata agree on the exact commit and version. Publish the feed only after every referenced artifact is downloadable and verified.
- [ ] Keep application release names, core/asset pins and user-facing version reporting coherent. Use a monotonic numeric bundle build number for ordering and keep prerelease labels separate where macOS metadata requires numeric versions. Never reuse build numbers or compare version strings lexicographically.
- [ ] Support manual checking, consent-controlled periodic checking, release notes, current/available version, download progress, cancellation/retry, Skip and Remind Later. Install/restart requires the user's approval and cannot interrupt active gameplay.
- [ ] Define stable and beta channels explicitly. Stable excludes prereleases; beta is opt-in. Exclude drafts, incompatible macOS/architecture builds, missing signatures, withdrawn candidates and older/equal versions. Do not rely solely on GitHub's latest-release shortcut to discover beta releases.
- [ ] Verify the update archive's EdDSA signature against the embedded trust key and verify the app's expected signing identity/bundle identity; use notarized artifacts and HTTPS. Checksums are useful integrity metadata, not a replacement for authentication. Keep private Apple/updater signing keys outside public CI, repository content and logs.
- [ ] Before replacement, stop gameplay through the acknowledged save path and flush metadata, SRAM and resume state. A save failure blocks restart and offers retry/cancel. Never force-terminate a still-saving or hung core to make an update look successful.
- [ ] Stage installation safely outside the running bundle. Handle low disk space, interrupted downloads, read-only DMGs, permissions, app translocation and installer failure with clear actions and a still-usable existing installation wherever safely recoverable.
- [ ] Preserve application-data paths, ROM IDs, labels, favorites, controllers, battery saves and state compatibility. Back up metadata before migration and provide a tested recovery path using the previous signed installer and compatible data backup; do not claim that arbitrary binary downgrades can read newer schemas.
- [ ] Keep first-install instructions for older builds that do not contain an updater. Prove production v0.8.0 to v0.9.0 installation in-app and retain v0.9.0 as the old build for the v0.10.0 acceptance test.

**Acceptance:** an installed signed v0.8.0 discovers, downloads, verifies, installs and relaunches signed v0.9.0 without opening a browser or requiring a manual app replacement. Compare the library and progress before/after; the same compatible state must still load. Test offline checks, invalid signature, incomplete feed entry, wrong architecture/minimum OS, rejected beta, cancellation, interrupted download, save failure and insufficient disk space. No unsafe candidate is installed; no failed check prevents offline play.

**Primary areas:** native updater adapter, Godot settings/update UI, release workflow/scripts, appcast generation/publication, signing configuration and data migration tests. The updater replaces the complete signed app; it does not remotely replace the core or fetch arbitrary executable plugins independently.

### 10. v0.10.0: integrated SNES Mac release and visual acceptance

**Status:** planned. Consolidate the product; do not use this milestone to introduce another platform or console.

**Deliverables**

- [ ] Run the complete first-use journey from the published installer: open, import a folder/ZIP, identify games, browse the 3D shelf, edit a label, launch, save/load, exit, reopen and resume.
- [ ] Demonstrate a real signed v0.9.0 to v0.10.0 update through the app, then repeat the same library/game/state flow. Also test a clean installation and migrations from an early v0.1 library.
- [ ] Review every required screen, all cartridge angles, labels, shadows, spacing, alignment, typography, focus and motion on actual Retina/non-Retina configurations available for testing. Use the compact accessible view without compromising the default 3D showcase.
- [ ] Profile 1-, 12-, 100- and 1,000-entry libraries using redistributable/synthetic fixtures. Enforce bounded caches, virtualized browsing and no unnecessary model downloads or background rendering during play.
- [ ] Complete reliability tests for import interruptions, missing files, migration failures, corrupt states, controller reconnects, sleep/wake and failed updates. Document the known in-process core-hang limitation and a non-destructive recovery route; do not promise process isolation that is not implemented.
- [ ] Fix all critical/high-severity data-loss, crash, wrong-game-selection, update-authentication and launch blockers. Record remaining lower-severity issues explicitly rather than labeling the product universally compatible.
- [ ] Finish onboarding, keyboard/controller help, privacy-safe diagnostics, About/license credits, save/data backup guidance, support matrix and release notes. No private paths, ROMs, saves, proprietary labels or signing material enter public artifacts.
- [ ] Rebuild and publish reviewed, signed/notarized artifacts, exact corresponding source and verified appcast entries from the same immutable release revision. Capture final owner-facing visual and interaction evidence.

**Acceptance:** the full product outcome at the top of this plan is demonstrable on a standard-user Apple Silicon Mac from downloaded artifacts, with no developer tooling or required online service. All ten milestone acceptance records are linked, visual review is complete, and a real in-app update preserves a playable library and loadable compatible progress. This is a complete SNES-focused milestone, not an automatic claim of v1.0 or support for every SNES title.

**Primary areas:** integration tests, UI polish, performance, docs and release packaging across the existing architecture. No new platform/framework migration.

## Quality gates and measurement

These are proposed acceptance targets, not benchmarks already achieved. Establish the reproducible baseline during v0.2-v0.4 on a documented Apple Silicon Mac, preferably an M1-class 8 GB reference machine with local SSD, a 1280x720 logical viewport and a recorded renderer/display configuration. Report cold and warm measurements separately.

| Concern | Target and required evidence |
| --- | --- |
| Browse responsiveness | Aim for 60 Hz presentation during shelf interaction, with p95 frame time at most 20 ms and no recurring stalls over 100 ms after warm-up. Selection feedback should arrive within 100 ms. Record a real trace, not just an average FPS counter. |
| Large library | Reach/search all 1,000 synthetic entries; warm search results within 150 ms after a documented debounce and first useful cached library content within 2 seconds. Import/hash/image decoding must not block input. |
| Memory/energy | Initial library-mode resident-memory budget: 1 GiB on the reference machine. Record actual GPU/texture residency, cache limits and 50 browse/detail/game-return cycles; no unbounded growth. Hidden/minimized/gameplay states stop unnecessary showcase work. |
| Cartridge fidelity | Review hero/front/top/rear/close-up views, multiple labels and neutral fallback in the exported Mac app. No texture bleeding, stretched labels, clipped silhouettes or stale-title/model combinations. |
| Progress safety | Real-core state restore plus app-restart tests; atomic write failure/retry tests for SRAM, states and metadata; incompatible states never silently apply. |
| Distribution/update | Downloaded-artifact Gatekeeper acceptance and two-real-build update evidence. Verify source/build/feed alignment and user-data preservation, including deliberate failure cases. |

Adjust a numeric budget only with a recorded measurement and an explicit explanation of the tradeoff. Do not hide poor 3D performance by silently making the primary view a static gallery. Native audio, hardware input, visual approval and update installation remain manual/native gates even when CI is green.

## Execution and completion rules

Implement one bounded milestone at a time. Keep each one usable, update this plan with its real status/evidence and remaining blockers, and follow the normal same-commit changelog rule for implementation work. Patch releases may fix earlier milestones without widening this ten-version scope.

Before marking a milestone complete, run the applicable pinned formatting, Clippy, Rust tests, real-core checks, Godot import/UI smokes, migration/error tests and publication audit. UI work additionally needs native visual/input evidence. Releases additionally need downloaded signed-artifact acceptance. Report unavailable hardware or failed checks explicitly; compilation is not product acceptance.

A release record includes source commit, tag/build number, supported macOS/architecture, core/model/updater pins, relevant data/state schemas, tests actually run, manual evidence, known limitations, artifact checksums and signing/notarization results. Never pre-check future work or publish a release merely because planning/code changes were committed.

### Final integrated checklist

- [ ] Download and install on a supported Mac without a development environment.
- [ ] Import user-owned SNES files, folders and ZIPs without modifying originals or duplicating identical bytes.
- [ ] Browse a clean, responsive, genuinely 3D cartridge collection with correct selection and attractive neutral/individual labels.
- [ ] Launch the selected ROM in-window with audible sound and working keyboard/gamepad input.
- [ ] Save/load manual and quick slots, restart and resume, while preserving independent battery saves.
- [ ] Detect an approved GitHub release and install/relaunch it from the app after user approval.
- [ ] Preserve library metadata, ROM identities, artwork choices and compatible progress through a real update.
- [ ] Pass the visual, reliability, performance, rights/provenance and signed-distribution gates with linked evidence.

## Deferred after these ten versions

Additional consoles; Intel Mac support; [Steam Deck/Linux distribution](https://github.com/lincolnaleixo/retrolife/issues/4); Windows/mobile; cloud saves/accounts; netplay; rewind/run-ahead; achievements; advanced shader catalogs; automatic ROM acquisition; broad online artwork scraping; arbitrary core/plugin downloads; independent runtime model updates; and an isolated emulation process. Preserve architectural seams where inexpensive, but none of these may displace the SNES Mac, 3D library, save-state or updater outcomes above.

## References and evidence entry points

Repository status and implementation: [architecture](docs/architecture.md), [release instructions](docs/releases.md), [development rules](rules.md), [published beta.2](https://github.com/lincolnaleixo/retrolife/releases/tag/v0.1.0-beta.2), [frontend shell](frontend/godot-ui/scripts/main.gd), [managed library](crates/retrolife-library/src/lib.rs), [emulation worker](crates/retrolife-emulation/src/lib.rs), and [source-release workflow](.github/workflows/release.yml).

Creative dependency: [cartridge collection](https://github.com/lincolnaleixo/retro-cartridge-models), [pinned neutral-model manifest](https://github.com/lincolnaleixo/retro-cartridge-models/blob/a5a184ff1b463b540c56a081e1da625f70067d7a/assets/snes-ntsc-u/versions/0.1.0.json), and the collection's license, credits and notices. Refer to the manifest for exact package/GLB checksums rather than trusting a filename.

Technical references checked for this planning revision: [Godot GLTFDocument](https://docs.godotengine.org/en/stable/classes/class_gltfdocument.html), [libretro serialization contract](https://docs.libretro.com/development/cores/developing-cores/), [Sparkle setup](https://sparkle-project.org/documentation/), [programmatic/non-Apple-toolkit integration](https://sparkle-project.org/documentation/programmatic-setup/), [update publication](https://sparkle-project.org/documentation/publishing/), and [Sparkle security changes](https://sparkle-project.org/documentation/security-and-reliability/). These guide implementation; compatibility with the project's exact pinned Godot/export configuration still requires the early native proof above.
