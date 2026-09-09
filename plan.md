# RetroLife plan

## Direction

One public Rust/Godot application with integrated emulation and a polished game library. Creative cartridge assets remain independently versioned.

## Current — First signed playable SNES release

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

Next session: test the downloaded beta.2 on Apple Silicon, record actual gameplay/audio/controller/save results in issue #1, and fix any observed failures before the next version. Review and merge the prerelease-policy and DMG-tooling pull requests through required CI; retain immutable published versions.

## Future

1. [Design and approve](https://github.com/lincolnaleixo/retrolife/issues/2) the 3D library experience, including navigation, accessibility and performance.
2. Integrate versioned cartridge assets with explicit provenance and neutral fallbacks.
3. [Add core-compatible](https://github.com/lincolnaleixo/retrolife/issues/3) save states, then separately designed synchronization.
4. [Validate Steam](https://github.com/lincolnaleixo/retrolife/issues/4) Deck/Linux distribution, then additional consoles.

## Completed

Migration planning and scoped source audits established the current architecture and publication boundary. Historical deployment, media and native frontend work is not an active dependency.

## Verification evidence

Clean-checkout Linux and native Apple Silicon checks pass: formatting, Clippy, 32 Rust unit tests, real bsnes-jg video and battery-save round-trip/retry checks, and Godot import/local-library/input-mapping smokes. The pinned core and Rust bridge compile on Apple Silicon. Native gameplay and input smokes pass; the first-import failure was isolated and corrected with generated extension registration before editor import. These checks do not establish audible output, physical controller acceptance, a sustained gameplay session, or a sustained hands-on acceptance result. Those gameplay checks remain release conditions above.

A local arm64 app export also starts and exits successfully; engine and both native libraries are arm64, the bundle identifier is correct, and a targeted packaged private-path scan is clean. The later published app passed Developer ID signing, Apple notarization, stapling, Gatekeeper and transferred-ZIP startup verification. The beta.2 DMG passed notarization, stapling, disk-image verification and mounted-app signature/Gatekeeper checks; its transferred SHA-256 matched the signing-machine output.

Public hosted CI passes. The application and Rust dependency source bundles were extracted together and all 32 Rust unit tests passed with `--locked --offline`; the pinned core source is packaged separately. Final versioned archives must be regenerated from the release commit.
