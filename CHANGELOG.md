# Changelog

All notable changes are recorded here. Versions follow Semantic Versioning.

## Unreleased

- Serve search, details and collection reads from a reconciled in-memory snapshot while the folder worker scans; launch verifies only the selected game. Preserve import failure notices across successful collection refreshes and leave user download staging files untouched.

- Record the reviewed MIT license choice for the ZIP reader’s pinned, UEFI-only r-efi dependency; keep unreviewed license changes blocked.

- Pin ZIP parsing to 9.1.0, including the upstream extraction security fixes required by the release vulnerability gate.

- Discover added, renamed, replaced and removed SNES ROMs automatically, including bounded single-game ZIP archives; retain game identities for saves and progress, skip incomplete files, and refresh the collection from background scans without interrupting gameplay.
- Connect existing ROM folders without requiring an application-created index and clear resolved missing-file notices.

- Keep imported ROM filenames readable, disambiguate name collisions, and reconnect renamed files by verified contents without changing game identity, saves or progress. Retain compatibility with existing hash-named libraries and interrupted imports.
- Use the native folder chooser for ROM storage and private 3D collections, starting at the configured folder or Documents when that location is offline. Restore storage settings after choosing or canceling, and keep a compact fallback on platforms without native dialogs.

- Make updater-enabled signed releases the delivery path for everyday Mac installations, document one-time migration from development builds, and preserve separately installed private collections across app updates.
- Include the public brand assets in the isolated updater UI fixture so clean CI imports and update-panel checks can run without any private model or artwork dependency.
- Build public releases with original procedural presentation and no private model downloads. Reject staged owner resources before export, declare the asset boundary in release metadata and verify it in the exported application. Preserve explicit owner staging and external collection loading.
- Report notarization validation phases and exit codes without exposing local paths or tool output, retry bounded host/service failures, and keep publication blocked when ticket validation still fails.
- Exercise the current collection-to-game launch flow in the real-core regression and reserve save-state shortcuts in the controller-remapping fixture; run collection, input ownership and asset-boundary checks in public CI.

- Add a cartridge collection between console selection and the full game presentation. Browse a centered cartridge with neighboring games and side arrows, select it to open its page, and return to the same collection position. Keep previews and selection music scoped to the game page, with neutral empty and single-game states.
- Separate the game's box and cartridge into independent 3D displays with room between them, distinct drag/zoom targets and individual captions. Clicking the box opens its inspector; clicking the cartridge on the game page plays. Preserve keyboard/controller access, modal focus, bounded model resources and absent-box fallbacks.
- Exercise the three-page navigation and inspect/play distinction, independent model transforms, visible neighbor layout, media ownership and responsive presentation with synthetic fixtures and local visual captures.

- Rotate and zoom the selected box and cartridge as one rigid, physically separated assembly. Align their resting bases, fit the camera at every inspection angle and ground the contact shadow; remove independent hover and bob that could make the models intersect. Exercise 405 rotation/zoom/aspect combinations and retain click-to-play and missing-model fallbacks.
- Turn selection backdrop artwork into a subdued per-game color wash so characters do not repeat behind the box. Give the optional official publisher mark a compact, contrasting plate beside the system name, retaining private asset loading and neutral missing-logo behavior.

- Keep short selection layouts at 1024×720 and similar narrow windows compact, preventing the synopsis and preview from pushing soundtrack controls or navigation below the window.

- Show the selected game’s external 3D box and cartridge together as one collectible composition. Reuse the existing validated box loader, retain only one selected box, and preserve click-to-play, shared drag/zoom inspection, keyboard/gamepad navigation and cartridge-only/text fallbacks.
- Replace the full-height selection panel with a continuous subdued artwork canvas, a bounded video preview, concise opening synopsis and responsive typography. Align the optional publisher mark with the system name and generate logo mipmaps for clean scaling; keep private artwork outside the app.

- Give active gameplay exclusive ownership of mapped controller input before GUI navigation, so Circle remains SNES A and face buttons cannot activate a focused fullscreen control. Keep library window dragging out of fullscreen and route in-game fullscreen shortcuts only through gameplay.
- Soften the selection dossier with a translucent background, center its content, add optional checksum-verified external publisher logos, and replace tiny music text with a speaker toggle, styled volume track and percentage. Missing publisher artwork retains its text fallback.

- Recompose game selection around a narrow illustrated dossier and a brighter artwork stage, inspired by ES-DE theme layouts. Keep copy bounded, integrate a clickable video with a small watch caption, replace full-width preview/music controls with compact controls, move collection count to the lower edge, and reduce the selected 3D cartridge. Compact windows suppress long synopses while preserving preview, navigation and neutral missing-media behavior.

- Scale the inline game preview with the window height (140–400 pixels) so large displays show meaningful gameplay footage beside the cartridge instead of a tiny fixed-height thumbnail.

- Make Super Mario World's Journey progressive: thirteen automatic discoveries, early power-up/Yoshi/Dragon Coin events, separate named keepsakes and later castle rewards. Hide future spoilers and move completed discoveries into Collection while preserving existing verified progress.
- Show a silent local OGV preview directly beside the selected game after a short delay, with original-art fallback, reduced-motion support and playback stopped during gameplay/dialogs. Reduce the selected cartridge by 24%, tighten typography and darken the scenery backdrop for readability.
- Keep game art and captured preview media in optional private packs; ScreenScraper credentials remain entered in Game media and never included in source. Validate staged native build, journal/media UI contracts and publication boundaries.

- Add real SNES save states with six manual slots, a Quick save slot and an automatic pre-load Recovery point. Show saved-frame thumbnails and timestamps in a paused Saved moments browser, with overwrite/load confirmation and F5/F6/F7 shortcuts. Serialize and restore only on the emulation worker, atomically store bounded checksummed files, validate game/core compatibility, clear stale input/audio and reset Journey transition evidence on load. Preserve cartridge-save storage and reject unsafe or corrupt restores with recoverable status.

- Make local game previews discoverable beside selection details and add optional per-game OGG, MP3 or WAV selection music with a separate saved volume. Stop collection audio before gameplay, during previews and when leaving game selection; preserve silence for games without media. Keep MP4 previews explicitly external and OGV previews inside RetroLife. Validate imported music and preserve existing assets when ScreenScraper reports missing media or offers an unsupported video.

- Open Game settings during a session from the header, F9 or the pause menu. Pause automatically and keep controls, shader previews and existing RetroLife preferences under one pause state; closing restores the previous play state. Persist game audio volume, expose fullscreen and Journey visibility, and isolate held inputs while configuring or returning to play.
- Prefer optional external PNG illustrations for custom Journey chapters and Rewards, retaining SVG compatibility and neutral fallbacks. Honor per-game pixel-art packs with nearest filtering and integer-scaled keepsakes. Keep game artwork in the private collection; changing presentation never unlocks a reward or enables unsupported games.

- Add in-game Super Nintendo display presets: Original, Smooth, Scanlines and CRT, with frozen-frame previews, adjustable intensity and persisted system preferences. Opening the shader panel pauses gameplay and releases inputs; closing restores the prior play/pause state. Effects apply only to the game image and adapt to frame resolution and window size. Keep the floating options compact on large displays, and restore pause/exit controls if saving fails while leaving a preview.

- Give supported custom Journeys larger illustrated chapters and full-color collectible artwork, with per-event colors, region captions and keepsake names from an optional bounded external theme. Supported games without art keep a neutral presentation; missing reward illustrations in partial packs consistently ignore per-card custom names and colors in Journey and Rewards. Hide the gameplay Journey column and toggle for unsupported games, omit them from Rewards, and retry temporary support failures without losing the visibility preference. Themes never enable detection or change progress.

- Preserve macOS privacy permission continuity across local app updates with a pinned Apple Development signing identity. Add a dedicated installer that verifies signatures and designated requirements, refuses running-app replacement and ad-hoc fallback, and backs up the previous application with rollback. Keep ROM locations, saves, artwork and existing privacy settings unchanged. The first migration from an ad-hoc build can require one new authorization.

- Replace manual Journey checks and elapsed-time gifts with verified Super Mario World (USA) gameplay events: Yoshi's Island stage clears, secret exits, Koopaling castles and Bowser's ending. Read SNES memory on the emulation worker after each frame, match the loaded ROM hash, and reject menus, demos, death exits, unsupported versions and unavailable memory. Keep the original version-one journal in an exact backup and archive legacy records without treating them as verified XP. Journey and Rewards now show read-only event rewards and automatic unlock notices.

- Add a library-wide Rewards collection with global XP and per-game keepsakes, shared custom interface icons, a readable typography theme and an original RetroLife boot splash. Preserve reward IDs and saved progress.
- Keep the integrated gameplay header draggable, support fullscreen without key-repeat flicker, and persist the Show/Hide Journey preference while returning space and focus to the game.
- Give game selections an optional local scenic background, description, release details and explicit video preview. Clear unavailable or stale presentation data and keep games without artwork neutral.
- Add in-app ScreenScraper configuration with session-only credentials, console-scoped explicit search/selection, bounded local media downloads, offline pack import and sanitized provenance. Keep artwork external and support explicit local MP4-to-OGV conversion for inline playback. Live authenticated service acceptance is pending.

- Add optional per-game Journey art packs with a landscape hero, illustrated chapter cards and a two-column keepsake collection. Keep artwork external, cache it per selection, scope matching by console, clear stale textures and show neutral text when custom art is missing. Preserve existing milestone IDs, XP, paused time, confirmation rollback and reversible rewards.

- Integrate the library into a borderless game-style window with a compact contextual header, static studio background, window dragging, fullscreen, minimize and safe quit. Remove bottom command and storage bars. Click console art to enter its collection and playable cartridge art to start; preserve drag/zoom inspection, keyboard/gamepad access and a missing-model fallback. Keep Search available after empty results and test vertical drag rejection.

- Fix runtime GLB texture-coordinate remapping: preserve repeating normal/roughness UVs separately from baked occlusion atlases, preventing swollen-looking plastic on console previews. Generate mipmaps for data textures and rebalance the preview lights. Keep private source models unchanged and add an original two-UV regression fixture.

- Present consoles one at a time in a 3D carousel and exclude systems without library games. Support side buttons and left/right navigation, preserve selection on refresh and handle empty collections without stale actions.

- Replace console-gallery images with interactive local 3D models for all seven systems. Drag rotates each console, double-click resets it, and a separate button opens its games. Preserve loaded previews across navigation and suspend rendering outside the visible gallery.

- Start in a console gallery, then open that console's games. Add a rotatable, zoomable local 3D box inspector and a dedicated RetroLife app icon.
- Fit box-camera depth precision to the physical model and use anisotropic texture sampling. Pin the reviewed original icon bytes in the publication audit without admitting other binary assets.
- Give seven known games distinct Journey chapters, challenge descriptions, reward collections, accent colors and local artwork. Unknown games keep a neutral journal, and challenge completion remains explicitly self-reported.

- Record the verified local workspace build and the public CI blocker: the pinned 3D packages now require private repository access. Keep the feature PR in draft and preserve the private-asset boundary.

- Add a library workspace with direct Play, console and game presentation, an explicit ROM storage location and a private local 3D collection link. ROM copying verifies identities and keeps originals; new imports use console folders while existing layouts remain readable. Offline volumes never fall back to internal storage.
- Add visual SNES controller mapping with a highlighted 3D target, keyboard/gamepad capture, persistent bindings, duplicate rejection and cancellation/timeout rollback. Gameplay now uses the configured InputMap consistently.
- Add a persistent personal Journey beside gameplay: emulator-time quests, self-reported game challenges, XP, levels and eight collectible rewards per game. Rewards are idempotent, can be corrected, and survive reload; pauses add no time.
- Wait for save acknowledgement before closing the window and use an elapsed-time stop deadline instead of a frame-count deadline, avoiding false save timeouts on fast presentation loops.

- Follow the renamed Retro 3D Library repository in canonical model-download and tag-pinned label URLs, current documentation and preview help. Preserve every model version, release tag, manifest commit, file checksum and the existing bundled notice-directory path.

- Pin the approved Super Mario World labels to collection release 0.2.0: the front print has localized scan wear removed, while its artwork and folded layout are preserved. Use the canonical reproduction paths and verified checksums; the rear print and all neutral model dependencies remain unchanged.

- Update the pinned Nintendo 64 neutral model to 0.2.0 with a smoother crown, recessed rear wordmark, connector guide and board substrate, and refined Gamebit screws. Preserve its physical scale and front/rear artwork mapping. The neutral and local Super Mario 64 preview imports passed Godot 4.7.2 label-UV, five-media switching, bounds and routed-control checks; front, rear and top views were inspected.

- Add neutral Nintendo 64 and NES presentation profiles with physical front/rear artwork proportions, folded NES top-label handling and safe fallback framing. Expand the isolated preview to five media types with numbered selection, per-model rotation, focus and front/rear captures; optional game examples stay local and missing examples retain verified neutral inputs. SNES-only ROM import and emulation support are unchanged.
- Pin Nintendo 64 and NES 0.1.0 packages from the model repository with exact archive/GLB hashes and independent credits, license and notices; both export presets include the new license files. The five-model neutral and local reproduction previews passed Godot 4.7.2 surface, UV, pooled-switching and routed-control checks.

- Follow the model repository's physical `assets/templates/<console>` and `assets/reproductions/<console>/<game>` hierarchy in documentation and local preview notices, while retaining compatibility with older source checkouts. Release locks, package IDs and tag-pinned artwork URLs remain unchanged.

- Documented the English source-library layout in `retro-cartridge-models`: neutral templates by console and reproductions by console and game, with a verified download command. Runtime model staging and pinned asset versions remain unchanged.

- Use neutral white lighting and reflection colors in the local media preview, avoiding warm and blue casts over imported game-label inks. Owner artwork retains every surface's maps and finish, with isolated material copies restoring the model repository's lower print specular response that Godot's glTF importer ignores. Godot 4.7.2 import/material, media-profile and routed preview-control checks passed with the regenerated local examples.
- Replaced the PlayStation case with a standalone CD, including an annular fallback and hole-preserving front artwork. Removed case/lift controls from the preview and added CD face flipping.
- Pinned the already-published Mega Drive and PlayStation 0.1.0 model packages with verified archive/file hashes and independent notices. Builds prepare all three neutral models from the model repository.
- Added optional local Sonic 1 / Crash Bandicoot examples generated by the model repository; embedded artwork is preserved only in the disposable owner preview and excluded from release assets.

- Added focused inspection and a studio reflection environment to the local media preview: opening the PlayStation case frames it alone, and lifting the complete disc reveals the fixed retention hub and clear tray. Closing or resetting reseats the disc exactly; routed input verification covers these transitions.
- Preserve imported paper normal and roughness maps when applying front/rear game artwork, including synthetic covers and pooled platform changes.
- Updated the Mega Drive artwork canvas for a 74 × 67 mm unfolded label, with a dedicated 7 mm title band matching the rebuilt cartridge's top fold. Local model previews use the reconstructed physical media without changing the published asset lock.
- Matched rear artwork proportions to the rebuilt Mega Drive molded panel and the PlayStation's continuous 151 × 118 mm rear/spine insert; rear composition does not reuse the front label's top-fold title band.

### Added
- Presentation profiles for Mega Drive cartridges and PlayStation 1 jewel cases, with safe pooled model switching, shared resources, aspect-aware front/rear artwork and platform-scoped collection labels. SNES import and emulation support are unchanged.
- An explicit local-only three-model staging command, directly openable Godot preview with rotation/zoom and an opening PlayStation case, synthetic rendered captures, and a focused media-profile smoke integrated into UI checks. The immutable released SNES lock and release stage are unchanged.
- Optional Sparkle binary delta updates: the release workflow hands the previous signed archive to the protected host helper, which builds and verifies a format-4 delta, signs it with the same Ed25519 key as the ZIP, records it in the update metadata and SHA256SUMS, and the feed exposes it under `<sparkle:deltas>`; clients fall back to the full archive whenever a delta is missing or does not apply. Activation needs a one-time helper install on the signing Mac.
- Download approved per-game labels on request: when a matching game has no verified artwork, the library requests only that pinned package URL from the cartridge collection, verifies the SHA-256 against the committed index before installing it atomically into the user cache, and repaints the cartridge. The "Download approved labels" setting disables fetching, matching stays local, verified files are never silently replaced, and an unreachable collection falls back to the neutral label.
- Executor guide covering environment prerequisites, hard guardrails, the standard change/pull-request/release loop, verification commands, the owner-only acceptance gates and a recommended first task order; records the two long-lived branch policy in `rules.md`.
- Automatic main-branch macOS beta pipeline with credential-free native builds, separate protected signing/notarization, immutable GitHub releases, full source/notices/checksums and explicit public update-feed publication.
- Sequential beta allocation with numeric ordering, Apple suffix rollover, duplicate/stale-source protection and no publication on missing signing configuration.
- Real exported-app updater-availability probe, offline release contracts, unsigned macOS packaging regression and secure one-time environment configuration helper. Production publication still requires the maintainer's actual credentials.
- In-app macOS update checks, native menu entry, persisted stable/beta and automatic-download/install preferences using checksum-pinned Sparkle.
- A Rust-owned gameplay/save barrier preventing update checks or relaunch during an active session and rejecting game starts during installation.
- Versioned release packaging with an embedded Ed25519 public key, inside-out Sparkle signing, verified ZIP signatures and release metadata, plus automatic appcast publication from GitHub Releases.
- Offline updater/security contracts, Godot update settings tests and a native real-Sparkle test host with disposable keys and applications. New signed distribution acceptance remains pending.
- Cartridge-first Godot library with a pooled seven-model 3D carousel, interruptible transitions, local labels, compact search/import controls, selection restoration and accessible text/low-power views.
- Pinned neutral SNES model staging with archive/member checksums, offline inputs, independent notices and malicious-archive unit tests.
- Synthetic 10,000-game interface smoke and a separate hosted rendering workflow that captures the real UI without ROMs or proprietary artwork. Hands-on native macOS and physical-controller acceptance remain pending.
- A standard hosted Apple Silicon native core/interface check job without signing-machine access or credentials.
- A native carousel-to-core round-trip regression that retains the existing generated-ROM, video, input and save checks and exercises the new UI with the real managed backend.
- User-facing cartridge controls, artwork, resource-budget and verification documentation, plus independent asset notices in release packaging.
- Recorded published beta.1 ZIP and beta.2 DMG, completed signing verification and remaining hands-on acceptance in the roadmap for session handoff.
- Added a signed and notarized DMG packaging helper with an Applications shortcut for macOS testing releases.
- Linked the available signed beta from the README while retaining pending hands-on acceptance.
- Fresh public-ready Rust/Godot application baseline with an explicit source allowlist.
- Managed local SNES library, in-window emulation integration, and local battery-save work.
- Deterministic headless checks for local import, video delivery, pause/resume, and saved-session shutdown.
- Canonical development rules, roadmap, contribution and security guidance.
- Reproducible core build, publication audit, and macOS release tooling.

### Changed
- Recorded optional Sparkle binary delta updates as a v0.9 deliverable after the owner asked why in-app updates download the full signed archive.
- Paint the approved rear print too: the collection label pipeline carries front and rear exports, verifies both checksums against the committed index, and applies the rear artwork to the rear printed-information surface; without a rear export that surface keeps its unprinted finish.
- Make the cartridge feel livelier on owner feedback: stronger idle yaw, pitch and float amplitudes with a slightly quicker rhythm, more responsive drag rotation and a stronger pointer parallax; reduced motion and the bounded inspection limits are unchanged.
- Give the selected cartridge a visible idle sway and float, free drag inspection (360° yaw, bounded pitch) with damped follow, wheel/pinch and keyboard/trigger zoom with limits, and an `R`/right-stick-click reset. Wheel scrolling now zooms inspection instead of browsing, and reduced motion stops the idle movement while keeping manual inspection.
- Resolve approved collection labels for matching titles: normalize the game title locally and ignore region/dedup markers, paint the artwork across the actual continuous front-label mesh including the folded top, fix the label-surface lookup so the curved label mesh is used instead of the flat fallback quad, and record the pinned Super Mario World 0.1.1 label metadata in the asset lock. User artwork still wins, the neutral label remains the fallback, and release bundles stay free of commercial game artwork.
- Open the library shell at a 2K-class default window (2560x1440 content when the usable display fits it, otherwise near the usable area, never below the 1024x640 floor), raise the 3D render-viewport budget to 2560x1440, and add a headless window-layout smoke covering the sizing policy and floor.
- Expanded the plan roadmap with further owner-requested quality and operational items: macOS menu-bar/shortcut parity, gameplay display, volume and controller-remapping options, portable library backup, label-fetch privacy rules, battery-save backup rotation, safe quit during gameplay, install scheduling, app icon/branding, a consolidated end-user guide, diagnostics export, privacy statement, DMG presentation, compatibility matrix, visual/input/audio quality gates, release-identity recovery rehearsal, dependency/runtime maintenance and future localization, capture and fast-forward candidates.
- Recorded the owner's review of the installed beta: the library must open at a 2K-class default window, the hero cartridge must visibly move and support free 360° inspection, and per-game labels are sourced from the public cartridge collection; updated the design specification, milestones and quality gates, and refreshed the baseline to the updater-enabled beta.3/beta.4 releases.
- Adopted a ten-version SNES macOS roadmap with a cartridge-first 3D library design, explicit platform and architecture contracts, measurable quality gates and evidence rules for the upcoming milestones.
- Added a protected local-Keychain signing mode through a host-installed signer for the trusted Apple Silicon release runner, while retaining hosted App Store Connect API-key notarization and keeping private signing material off the repository.
- Feed the protected Sparkle private key to the host signer through standard input, validate its public-key pairing before signing and require it in local release preflight.
- Recorded passing real-Sparkle upgrade/relaunch and security scenarios on Apple Silicon, and kept the update dialog Close action visible at narrow window sizes.
- Connected the native updater to the Godot settings and Rust session lifecycle, and added signed release-feed tooling with isolated automated verification.
- Recorded completed cartridge implementation tasks separately from pending visual/physical acceptance and future milestones, with passing Linux and Apple Silicon evidence for revision 48bd6d2.
- Apply per-game labels to the actual curved model label surface, render each label only when it changes, and preserve local-image proportions.
- Refined hero scale, lighting and keyboard focus; kept desktop text readable at narrow window sizes and bounded the text fallback to the available height.
- Expanded verification with routed input events, preference persistence, resizing and seven real rendered capture states; retained small evidence artifacts instead of repeatedly uploading the debugging runtime.
- Preserved the concurrently merged signed-beta documentation and DMG packaging while integrating the cartridge-library implementation.
- Required alpha and beta builds to be distributed through GitHub Releases as explicitly labeled prereleases, with verification evidence and pending acceptance tests.
- Separated creative assets from application source and licensing.
- Replaced private deployment assumptions with local application storage and explicit build inputs.
- Isolated Godot user data under `io.github.lincolnaleixo.retrolife` and aligned the Apple Silicon export preset with the release signing flow.
- Made the gameplay exit flow wait for the native runtime to finish saving before returning to the library.
- Kept session metadata available until the native stop event confirms a completed save.
- Paired every fetched video frame with the core's actual dimensions, frame rate, sample rate, and display aspect ratio; frame advancement now follows a capped core-rate accumulator.
- Added complete SNES shoulder and face-button mappings, including keyboard L/R controls and a right-stick pause fallback, with deterministic bridge and Godot input smokes.
- Kept headless UI smoke runs free of Godot's retained audio playback handle while desktop and mobile builds retain live generator output.

### Fixed
- Preserve full-detail front and rear label meshes in the cartridge pool: generated Godot LODs distorted UV interpolation at the folded top and bent printed letters. Runtime label meshes are shared, while shell LODs and the pinned GLB remain unchanged.
- Keep the contact-shadow plane below the transformed cartridge bounds during idle, hover, rotation and zoom, eliminating the dark stripe across the lower shell. Clamp label textures at the folded UV border to prevent opposite-edge bleeding.
- Clear pointer tilt when leaving the stage, cancel interrupted pointer gestures when an overlay opens or the window loses focus, and apply the saved label-download preference at library startup.
- Extend cartridge regressions with extreme inspection bounds and hover interruption checks, and rendered evidence with folded-top, underside and rear views.
- Accept signed binary deltas in the updater's download allowlist (the previous check rejected every delta with a misleading error) and gate delta creation and feed advertising on `minimumDeltaSource`, so builds that predate the fix keep receiving the full archive instead of a rejected delta.
- Soften the label and rear materials' specular response too, after isolating a bright line across the lower shell to the label mesh's lit edge: the same treatment already applied to the shell now covers every cartridge material, so the seam and the folded-top corner read as matte plastic instead of a glowing crack or a floating plate.
- Apply label-proportioned artwork directly to the label surface at up to 2048 pixels with mipmapped anisotropic filtering instead of resampling it through the 1024 compositor, so the folded top stays crisp at grazing angles; shaped artwork and the neutral label keep the composed painter.
- Soften the cartridge shell's specular response with runtime material copies so the sharp molded seam no longer draws a bright highlight line under the showcase lights; the released GLB stays untouched, and the smoke pins the softened response.
- Correct the inspection drag direction: dragging right now turns the front to the right and dragging down tilts it down, as the pointer does, and the smoke pins the expected direction.
- Keep the label index working in exported applications: load the full label entry so the download address survives indexing, ship the committed index in both export presets, and pin that coverage in the style tests.
- Give the release publish job a 60-minute upload budget: slow runner transfers to GitHub Releases were exceeding the previous 15-minute limit, cancelling the job mid-upload and leaving an incomplete draft for the next queued source to supersede.
- Keep development-only collection labels out of release exports with an export exclusion and a verify-stage refusal; verify staged labels against a committed index whose checksums are checked against the asset lock; preserve semantic title words and sequel numbers while treating a parenthesized World marker as a region.
- Correct the stale 720x540 minimum-window statement in the cartridge guide and record the implemented 2K-window status and automated evidence in the roadmap.
- Reconciled README, release, update and cartridge documentation with the published updater-enabled betas and the automatic pipeline: beta.3 and later contain the cartridge interface and in-app updater, the automatic main-branch release is the normal publication path, and the first public signed-to-signed upgrade remains explicitly pending validation.
- Sanitize the pinned Godot template's public hosted-runner source paths before packaging and reject private build paths in the unsigned packaging regression.
- Give the update dialog an opaque, high-contrast surface so cartridge artwork cannot interfere with update controls.
- Preserve the pinned Sparkle downloader entitlements when re-signing embedded components, following the upstream manual-signing procedure.
- Require EdDSA verification before extracting update archives and align the native bridge with the pinned Rust formatter.
- Kept navigation hints visible in a 720 by 540 window when a long title and a multiline import error appear together; added a regression for that combined layout.
- Kept checksum verification compatible with Python installations without hashlib.file_digest.
- Corrected the environment API and explicitly typed pointer calculations identified by the first hosted Godot import; retained an isolated reproduction artifact and included hidden-directory evidence files.
- Removed the first-page-only library presentation limit and format game counts as integers instead of decimal bridge values.
- Retained the active session after battery-save failures so users can repair the destination and retry without discarding SRAM.
- Corrected native logging callbacks, bounded content/save reads, and shutdown delivery when the worker queue is full.

- Completed baseline provenance destinations and included the full LGPL notice in the application license bundle.
- Recorded hosted-check and native first-import blockers without claiming a signed release.
- Bootstrapped the built extension before first Godot import, preventing the clean-checkout editor shutdown crash on Linux and macOS.
- Verified the clean-checkout build and native Apple Silicon import, gameplay presentation, input contracts, and battery-save tests.
- Enabled the texture import format required by Godot’s Apple Silicon exporter.
- Extracted the arm64 engine from the official universal Godot template before final app signing.
- Replaced local Mach-O library install names with portable rpath identifiers before signing.
- Verified arm64 packaged startup and used the release template’s supported startup check instead of editor-only script arguments.
- Published the audited source repository independently of the pending signed release, using standard public GitHub Actions runners.
- Documented rebuilding the application with the bundled Rust dependency sources without registry access.
- Verified all Rust tests using the extracted corresponding-source bundles with registry access disabled.
- Clarified the native compiler prerequisite and test-only scope of offline Rust source verification.
