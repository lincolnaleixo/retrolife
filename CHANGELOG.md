# Changelog

All notable changes are recorded here. Versions follow Semantic Versioning.

## Unreleased

### Added
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
