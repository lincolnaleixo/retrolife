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
- [ ] Complete CI, dependency notices and release-source packaging.
- [ ] Exercise native macOS gameplay, input, audio and save restoration.
- [ ] Sign, notarize, staple and verify the downloaded app.
- [ ] Audit the complete final source and release artifacts.
- [ ] Publish the repository and immutable v0.1.0 prerelease.

Current release blocker: the signing environment is reachable but its Keychain needs unlocking before notarization can be verified. Native macOS gameplay acceptance is pending. Hosted CI could not start, and private branch protection is unavailable under the current GitHub plan; apply protection when the repository can become public. No signed release is claimed.

## Future

1. [Design and approve](https://github.com/lincolnaleixo/retrolife/issues/2) the 3D library experience, including navigation, accessibility and performance.
2. Integrate versioned cartridge assets with explicit provenance and neutral fallbacks.
3. [Add core-compatible](https://github.com/lincolnaleixo/retrolife/issues/3) save states, then separately designed synchronization.
4. [Validate Steam](https://github.com/lincolnaleixo/retrolife/issues/4) Deck/Linux distribution, then additional consoles.

## Completed

Migration planning and scoped source audits established the current architecture and publication boundary. Historical deployment, media and native frontend work is not an active dependency.

## Verification evidence

Clean-checkout Linux and native Apple Silicon checks pass: formatting, Clippy, 32 Rust unit tests, real bsnes-jg video and battery-save round-trip/retry checks, and Godot import/local-library/input-mapping smokes. The pinned core and Rust bridge compile on Apple Silicon. Native gameplay and input smokes pass; the first-import failure was isolated and corrected with generated extension registration before editor import. These checks do not establish audible output, physical controller acceptance, a sustained gameplay session, or notarized distribution. Those remain release conditions above.

A local arm64 app export also starts and exits successfully; engine and both native libraries are arm64, the bundle identifier is correct, and a targeted packaged private-path scan is clean. This local validation app is not a Developer ID signed/notarized release and has not been published.
