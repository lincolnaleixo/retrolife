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
- [ ] Sign, notarize, staple and verify the downloaded app.
- [ ] Audit the complete final source and release artifacts.
- [x] Publish the audited source repository.
- [ ] Publish the immutable signed v0.1.0 prerelease.

Current release blocker: the signing environment is reachable but its Keychain needs unlocking before notarization can be verified. Native macOS gameplay acceptance is pending. The audited source was made public by owner decision so standard hosted CI can run without a paid plan. Signing and gameplay acceptance remain release requirements. No signed release is claimed.

## Next: 3D cartridge library

Acceptance tracking: [issue #2](https://github.com/lincolnaleixo/retrolife/issues/2).

Purpose: replace the temporary text/card library with a controller-first 3D cartridge browser that makes the collection itself feel physical and collectible. The selected game should be the visual focus, with neighboring cartridges visible in perspective, while search, import and system controls stay available without dominating the screen.

Primary visual target: a dark full-window showcase with one centered cartridge at hero scale, nearby cartridges receding to the sides, subtle depth and motion, concise title metadata, compact system navigation and persistent controller hints. The first implementation is SNES NTSC-U and uses the independently versioned models from [`retro-cartridge-models`](https://github.com/lincolnaleixo/retro-cartridge-models).

Done when: a user can import multiple SNES games, browse them smoothly with gamepad, keyboard or mouse, immediately identify the selected title, open its details and launch it, recover cleanly from missing model or artwork data, and use the library without any network dependency. The interface must remain responsive with a synthetic large library and must not bundle proprietary game artwork as application source.

- [ ] Approve a focused visual spec for the cartridge browser: centered hero cartridge, visible left/right neighbors, dark showcase background, compact top-level system selector, selected-title metadata and unobtrusive bottom control hints.
- [ ] Remove the current large card-grid presentation as the primary library view and demote search, import, source/debug status and secondary filters into compact chrome or overlays so the cartridges remain the focal point.
- [ ] Define deterministic navigation for controller, keyboard and mouse: D-pad/arrows move one cartridge, LB/RB switch systems, A/Enter opens the selected game details, B/Esc returns, search has a dedicated action, and mouse click/scroll/drag has equivalent behavior.
- [ ] Preserve selection and scroll position when opening details, returning from gameplay, changing filters or switching systems.
- [ ] Pin exact releases of the SNES cartridge assets from `retro-cartridge-models`, record their provenance, verify release checksums, and keep large creative binaries outside the application Git history.
- [ ] Add a reproducible asset preparation step that fetches or consumes the pinned cartridge package, verifies it and stages only the required GLB/material resources for the Godot build and release process.
- [ ] Build a reusable Godot `Cartridge3D` scene around the SNES GLB with a stable transform, camera anchor, material slots, label surface, lighting hooks and neutral fallback materials.
- [ ] Add a runtime label pipeline that can use user-local or otherwise permitted artwork when available and can always generate a clean neutral label from game metadata when artwork is absent. Do not commit or redistribute proprietary game artwork as application-owned source.
- [ ] Implement the horizontal 3D carousel: selected cartridge large and centered, immediate neighbors smaller and offset in perspective, farther entries represented cheaply, and transitions driven by short interruptible tweens rather than blocking animations.
- [ ] Add restrained physical motion to the selected cartridge, such as a small idle tilt or pointer parallax, while keeping the normal browser camera controlled and readable rather than turning the library into a free-form 3D viewer.
- [ ] Add selected-game typography and metadata below or beside the hero cartridge with clear hierarchy for title, system and concise status. Avoid repeating technical source/debug strings in the primary visual hierarchy.
- [ ] Make ROM import feel integrated with the new library: newly imported games appear in the correct sorted/filter state, become selectable immediately and can animate into focus without rebuilding the whole scene.
- [ ] Instantiate only the selected cartridge and a small neighborhood around it, reuse pooled 3D nodes, prefetch nearby textures and keep off-screen entries as lightweight data so large libraries do not create one live 3D scene per game.
- [ ] Define texture-size, material and lighting budgets for Apple Silicon and provide graceful fallbacks for lower render quality, missing GLB assets, missing label textures and unsupported material features.
- [ ] Add responsive camera/layout rules for window resizing and common desktop aspect ratios so the hero cartridge never collides with navigation, title metadata or control hints.
- [ ] Add reduced-motion behavior, keyboard-visible focus, readable contrast and a non-3D textual fallback path so the library remains usable when motion or 3D presentation is disabled.
- [ ] Extend deterministic UI smokes to cover left/right navigation, rapid repeated input, system switching, detail round-trips, import insertion, missing-art fallback and missing-model fallback.
- [ ] Add a synthetic large-library performance fixture with no ROM content and verify that navigation remains responsive, memory use stays bounded and the active 3D node count is limited by the carousel window rather than total library size.
- [ ] Exercise the complete 3D library natively on macOS with keyboard, physical controller and mouse, then record performance and acceptance evidence before claiming the milestone complete.
- [ ] Update screenshots, user documentation, third-party notices and release-source packaging for the pinned cartridge assets without merging their independent license or version history into the application repository.

## Future

1. [Add core-compatible](https://github.com/lincolnaleixo/retrolife/issues/3) save states, then separately designed synchronization.
2. [Validate Steam](https://github.com/lincolnaleixo/retrolife/issues/4) Deck/Linux distribution.
3. Extend the 3D library to additional systems only after the SNES interaction, asset pipeline and performance model are proven.
4. Add additional emulation cores and system-specific presentation without weakening the local-library, licensing or release boundaries.

## Completed

Migration planning and scoped source audits established the current architecture and publication boundary. Historical deployment, media and native frontend work is not an active dependency.

## Verification evidence

Clean-checkout Linux and native Apple Silicon checks pass: formatting, Clippy, 32 Rust unit tests, real bsnes-jg video and battery-save round-trip/retry checks, and Godot import/local-library/input-mapping smokes. The pinned core and Rust bridge compile on Apple Silicon. Native gameplay and input smokes pass; the first-import failure was isolated and corrected with generated extension registration before editor import. These checks do not establish audible output, physical controller acceptance, a sustained gameplay session, or notarized distribution. Those remain release conditions above.

A local arm64 app export also starts and exits successfully; engine and both native libraries are arm64, the bundle identifier is correct, and a targeted packaged private-path scan is clean. This local validation app is not a Developer ID signed/notarized release and has not been published.

Public hosted CI passes. The application and Rust dependency source bundles were extracted together and all 32 Rust unit tests passed with `--locked --offline`; the pinned core source is packaged separately. Final versioned archives must be regenerated from the release commit.
