# Changelog

All notable changes are recorded here. Versions follow Semantic Versioning.

## Unreleased

### Added
- Cartridge-first Godot library with a pooled seven-model 3D carousel, interruptible transitions, local labels, compact search/import controls, selection restoration and accessible text/low-power views.
- Pinned neutral SNES model staging with archive/member checksums, offline inputs, independent notices and malicious-archive unit tests.
- Synthetic 10,000-game interface smoke and a separate hosted rendering workflow that captures the real UI without ROMs or proprietary artwork. Native macOS and physical-controller acceptance remain pending.
- Recorded published beta.1 ZIP and beta.2 DMG, completed signing verification and remaining hands-on acceptance in the roadmap for session handoff.
- Added a signed and notarized DMG packaging helper with an Applications shortcut for macOS testing releases.
- Linked the available signed beta from the README while retaining pending hands-on acceptance.
- Fresh public-ready Rust/Godot application baseline with an explicit source allowlist.
- Managed local SNES library, in-window emulation integration, and local battery-save work.
- Deterministic headless checks for local import, video delivery, pause/resume, and saved-session shutdown.
- Canonical development rules, roadmap, contribution and security guidance.
- Reproducible core build, publication audit, and macOS release tooling.

### Changed
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
