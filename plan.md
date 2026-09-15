# RetroLife plan

## Direction

One public Rust/Godot application with integrated emulation and a polished game library. Creative cartridge assets remain independently versioned.

## Current: First signed playable SNES release

Acceptance evidence: [issue #1](https://github.com/lincolnaleixo/retrolife/issues/1).

Purpose: establish a clean public baseline and a usable macOS Apple Silicon application.

Done when: a clean checkout builds without private dependencies; an imported game plays with sound and keyboard/gamepad input; local battery saves survive restart; the downloaded app passes signing, notarization and Gatekeeper; the final source and artifacts pass the publication audit.

- [x] Preserve current uncommitted work outside the replacement repository.
- [x] Preserve the previous public repository privately under its historical name.
- [x] Create the replacement privately with fresh history and selected source.
- [x] Establish English rules, changelog, licensing and roadmap.
- [x] Complete managed imports and persistence tests.
- [x] Complete owned Rust emulation session and Godot gameplay integration.
- [x] Verify pinned core build and redistributable test content.
- [x] Complete CI, dependency notices and release-source packaging.
- [ ] Exercise native macOS gameplay, input, audio and save restoration.
- [x] Sign, notarize, staple and verify the downloaded app.
- [ ] Audit the complete final source and release artifacts.
- [x] Publish the audited source repository.
- [ ] Publish the immutable signed v0.1.0 prerelease.

Current acceptance work: physical keyboard/gamepad gameplay, audible output, sustained-session behavior and user-game save restoration remain pending. Signing is resolved. [Beta.1](https://github.com/lincolnaleixo/retrolife/releases/tag/v0.1.0-beta.1) contains the signed ZIP; [beta.2](https://github.com/lincolnaleixo/retrolife/releases/tag/v0.1.0-beta.2) adds a signed, notarized and stapled DMG with an Applications shortcut. Both use application commit `a211f4c8b7908df2182a1c98f5dee41902500ab6`; beta.2 changes packaging only. Corresponding source and checksums accompany both releases. These testing prereleases do not close hands-on acceptance or claim the final v0.1.0 milestone.

Next acceptance step: review the cartridge implementation and verification in [PR #10](https://github.com/lincolnaleixo/retrolife/pull/10), retain the beta.2 baseline for comparison, and record actual gameplay/audio/controller/save results in issue #1. Build, sign and audit a new beta from reviewed source before claiming the downloaded app contains the new interface. Existing releases remain immutable.

## In progress: 3D cartridge library

Acceptance tracking: [issue #2](https://github.com/lincolnaleixo/retrolife/issues/2). Implementation and evidence: [PR #10](https://github.com/lincolnaleixo/retrolife/pull/10). Visual specification and user guide: [cartridge library](docs/cartridge-library.md).

Purpose: replace the temporary text/card library with a controller-first 3D cartridge browser that makes the collection itself feel physical and collectible. The selected game should be the visual focus, with neighboring cartridges visible in perspective, while search, import and system controls stay available without dominating the screen.

Primary visual target: a dark full-window showcase with one centered cartridge at hero scale, nearby cartridges receding to the sides, subtle depth and motion, concise title metadata, compact system navigation and persistent controller hints. The first implementation is SNES NTSC-U and uses the independently versioned models from [`retro-cartridge-models`](https://github.com/lincolnaleixo/retro-cartridge-models).

Done when: a user can import multiple SNES games, browse them smoothly with gamepad, keyboard or mouse, immediately identify the selected title, open its details and launch it, recover cleanly from missing model or artwork data, and use the library without any network dependency. The interface must remain responsive with a synthetic large library and must not bundle proprietary game artwork as application source.

Implementation status: the code, asset pipeline, documentation and automated verification tasks below are implemented. Owner visual approval and hands-on native acceptance are deliberately still open. A checked implementation task is not a claim of a new signed distribution or a passed physical-controller session.

- [ ] Approve a focused visual spec for the cartridge browser: centered hero cartridge, visible left/right neighbors, dark showcase background, compact top-level system selector, selected-title metadata and unobtrusive bottom control hints. The specification and rendered implementation are available for review.
- [x] Remove the current large card-grid presentation as the primary library view and demote search, import, source/debug status and secondary filters into compact chrome or overlays so the cartridges remain the focal point.
- [x] Define deterministic navigation for controller, keyboard and mouse: D-pad/arrows move one cartridge, LB/RB switch systems, A/Enter opens the selected game details, B/Esc returns, search has a dedicated action, and mouse click/scroll/drag has equivalent behavior.
- [x] Preserve selection and scroll position when opening details, returning from gameplay, changing filters or switching systems.
- [x] Pin exact releases of the SNES cartridge assets from `retro-cartridge-models`, record their provenance, verify release checksums, and keep large creative binaries outside the application Git history.
- [x] Add a reproducible asset preparation step that fetches or consumes the pinned cartridge package, verifies it and stages only the required GLB/material resources for the Godot build and release process.
- [x] Build a reusable Godot `Cartridge3D` scene around the SNES GLB with a stable transform, camera anchor, material slots, label surface, lighting hooks and neutral fallback materials.
- [x] Add a runtime label pipeline that can use user-local or otherwise permitted artwork when available and can always generate a clean neutral label from game metadata when artwork is absent. Do not commit or redistribute proprietary game artwork as application-owned source.
- [x] Implement the horizontal 3D carousel: selected cartridge large and centered, immediate neighbors smaller and offset in perspective, farther entries represented cheaply, and transitions driven by short interruptible tweens rather than blocking animations.
- [x] Add restrained physical motion to the selected cartridge, such as a small idle tilt or pointer parallax, while keeping the normal browser camera controlled and readable rather than turning the library into a free-form 3D viewer.
- [x] Add selected-game typography and metadata below or beside the hero cartridge with clear hierarchy for title, system and concise status. Avoid repeating technical source/debug strings in the primary visual hierarchy.
- [x] Make ROM import feel integrated with the new library: newly imported games appear in the correct sorted/filter state, become selectable immediately and can animate into focus without rebuilding the whole scene.
- [x] Instantiate only the selected cartridge and a small neighborhood around it, reuse pooled 3D nodes, prefetch nearby textures and keep off-screen entries as lightweight data so large libraries do not create one live 3D scene per game.
- [x] Define texture-size, material and lighting budgets for Apple Silicon and provide graceful fallbacks for lower render quality, missing GLB assets, missing label textures and unsupported material features.
- [x] Add responsive camera/layout rules for window resizing and common desktop aspect ratios so the hero cartridge never collides with navigation, title metadata or control hints.
- [x] Add reduced-motion behavior, keyboard-visible focus, readable contrast and a non-3D textual fallback path so the library remains usable when motion or 3D presentation is disabled.
- [x] Extend deterministic UI smokes to cover left/right navigation, rapid repeated input, system switching, detail round-trips, import insertion, missing-art fallback and missing-model fallback.
- [x] Add a synthetic large-library performance fixture with no ROM content and verify that navigation remains responsive, memory use stays bounded and the active 3D node count is limited by the carousel window rather than total library size.
- [ ] Exercise the complete 3D library natively on macOS with keyboard, physical controller and mouse, then record performance and acceptance evidence before claiming the milestone complete. Hosted Apple Silicon headless tests do not close this hands-on gate.
- [x] Update screenshots, user documentation, third-party notices and release-source packaging for the pinned cartridge assets without merging their independent license or version history into the application repository. The capture workflow and release helpers are updated; new signed artifacts still need release verification.

## In progress: In-app macOS updates

Implementation and verification: [PR #11](https://github.com/lincolnaleixo/retrolife/pull/11). User and release guide: [updates](docs/updates.md).

- [x] Add an in-app Check for Updates action and a native macOS menu item.
- [x] Persist automatic-check, optional automatic-install and stable/beta settings.
- [x] Integrate checksum-pinned Sparkle with EdDSA verification, Developer ID host checks, safe installation and relaunch.
- [x] Hold an update barrier across active gameplay and saving; do not restart to install during a game.
- [x] Embed the updater in the signed release workflow with correct bundle versions, independent notices and protected Keychain signing keys.
- [x] Generate signed-update metadata and automatically publish a restricted appcast from GitHub Releases on a separate distribution branch.
- [x] Add offline release/security contracts and Godot action/settings/error/layout regression tests.
- [x] Verify production native helper compilation and real Sparkle upgrade/relaunch on hosted Apple Silicon; record actual workflow results before closing.
- [ ] Publish and validate a newly signed updater-enabled beta, including signed-to-signed replacement, Gatekeeper and existing library/save preservation on the target Mac.

Existing beta.1 and beta.2 have no updater. They require a one-time manual installation of the first new updater-enabled signed build. Adding this code does not modify those immutable releases or claim a newly distributed app.

## Future

These later milestones remain unimplemented; they are not implied by completion of the cartridge presentation code.

1. [Add core-compatible](https://github.com/lincolnaleixo/retrolife/issues/3) save states, then separately designed synchronization.
2. [Validate Steam](https://github.com/lincolnaleixo/retrolife/issues/4) Deck/Linux distribution.
3. Extend the 3D library to additional systems only after the SNES interaction, asset pipeline and performance model are proven.
4. Add additional emulation cores and system-specific presentation without weakening the local-library, licensing or release boundaries.

## Completed

Migration planning and scoped source audits established the current architecture and publication boundary. Historical deployment, media and native frontend work is not an active dependency.

## Verification evidence

### In-app updater

[Updater run 35014267751](https://github.com/lincolnaleixo/retrolife/actions/runs/35014267751), for revision `5e3c49c8abbebe0f7ffcc5cb6da6d3b8f9d4e48e`, passed both the Linux contract/interface job and the standard hosted Apple Silicon native job. The production Objective-C helper compiled with warnings treated as errors. Sixteen Python release/security tests and the Godot updater interface smoke passed.

Nine native scenarios used real Sparkle with ephemeral signing keys, a local feed and disposable ad-hoc-signed bundles: settings/gameplay exclusion, no update, downgrade refusal, stable-only channel, incompatible OS, network failure, disallowed download origin, tampered signature, and a real beta.2-to-beta.10 bundle replacement/relaunch. The tests verified installed-bundle identity and unchanged user-data sentinels. The test-only user driver automated UI choices; it did not replace Sparkle download, verification or installation. No production signing credentials, real user libraries or game saves were used. Evidence is retained in the workflow artifacts and PR #11.

This does not establish a newly published Developer ID/notarized release, a signed-to-signed update of the packaged Godot application, or an upgrade using the public GitHub feed. Those distribution checks remain open above and require a new reviewed, signed release.

### Cartridge implementation

[Cartridge UI run 35006031561](https://github.com/lincolnaleixo/retrolife/actions/runs/35006031561), for application revision `48bd6d2d8fbda74105251c51af44d31d381a3ad0`, passed both the Linux presentation job and the standard hosted Apple Silicon native job. The latter verified arm64, built the pinned core and bridge, and ran formatting, Clippy, Rust tests, publication/dependency checks, asset tests, Godot import, gameplay/input checks and the 10,000-entry cartridge smoke. No signing credentials or trusted signing-machine access were used.

Nine Python asset-staging tests pass. The cartridge smoke covers all backend pages, bounded seven-model/nine-artwork-cache resources, rapid selection changes, search, import insertion, system-specific selection restoration, detail/gameplay-return callbacks, routed keyboard/controller/mouse events, preference persistence, resizing, model/artwork fallback and PNG input validation. CPU timing and allocation guards are regression checks, not proof of native rendered frame rate.

The real Godot renderer produced seven neutral-data captures: 1280x720 default, 720x540 narrow, 1600x900 wide, text, low-power, single-game and empty states. They are reproducible through `cartridge_library_capture.gd` and retained in the workflow evidence artifact without committing private game data or proprietary artwork.

`cartridge_native_smoke.gd` additionally extends the existing real-core regression with the actual managed-library-to-carousel-to-gameplay round trip. `scripts/check.sh` runs it in place of the original smoke while retaining the original checks through inheritance. Its latest execution result belongs in PR #10 and the workflow logs; adding the test alone is not evidence that it passed.

Still required: owner visual review, sustained rendering/performance on the target Mac, physical controller and audible output, user-game save restoration, and a newly built/signed/audited cartridge-library beta. Existing beta.1 and beta.2 do not contain this new interface.

### Baseline and published testing releases

Clean-checkout Linux and native Apple Silicon checks pass: formatting, Clippy, 32 Rust unit tests, real bsnes-jg video and battery-save round-trip/retry checks, and Godot import/local-library/input-mapping smokes. The pinned core and Rust bridge compile on Apple Silicon. Native gameplay and input smokes pass; the first-import failure was isolated and corrected with generated extension registration before editor import. These checks do not establish audible output, physical controller acceptance, a sustained gameplay session, or a sustained hands-on acceptance result. Those gameplay checks remain release conditions above.

A local arm64 app export also starts and exits successfully; engine and both native libraries are arm64, the bundle identifier is correct, and a targeted packaged private-path scan is clean. The later published app passed Developer ID signing, Apple notarization, stapling, Gatekeeper and transferred-ZIP startup verification. The beta.2 DMG passed notarization, stapling, disk-image verification and mounted-app signature/Gatekeeper checks; its transferred SHA-256 matched the signing-machine output.

Public hosted CI passes. The application and Rust dependency source bundles were extracted together and all 32 Rust unit tests passed with `--locked --offline`; the pinned core source is packaged separately. Final versioned archives must be regenerated from the release commit.
