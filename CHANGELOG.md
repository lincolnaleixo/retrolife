# Changelog

All notable changes are recorded here. Versions follow Semantic Versioning. No release has been published from this repository yet.

## Unreleased

### Added
- Fresh public-ready Rust/Godot application baseline with an explicit source allowlist.
- Managed local SNES library, in-window emulation integration, and local battery-save work.
- Deterministic headless checks for local import, video delivery, pause/resume, and saved-session shutdown.
- Canonical development rules, roadmap, contribution and security guidance.
- Reproducible core build, publication audit, and macOS release tooling.

### Changed
- Separated creative assets from application source and licensing.
- Replaced private deployment assumptions with local application storage and explicit build inputs.
- Isolated Godot user data under `io.github.lincolnaleixo.retrolife` and aligned the Apple Silicon export preset with the release signing flow.
- Made the gameplay exit flow wait for the native runtime to finish saving before returning to the library.
- Kept session metadata available until the native stop event confirms a completed save.
- Paired every fetched video frame with the core's actual dimensions, frame rate, sample rate, and display aspect ratio; frame advancement now follows a capped core-rate accumulator.
- Added complete SNES shoulder and face-button mappings, including keyboard L/R controls and a right-stick pause fallback, with deterministic bridge and Godot input smokes.
- Kept headless UI smoke runs free of Godot's retained audio playback handle while desktop and mobile builds retain live generator output.

### Fixed
- Retained the active session after battery-save failures so users can repair the destination and retry without discarding SRAM.
- Corrected native logging callbacks, bounded content/save reads, and shutdown delivery when the worker queue is full.

- Completed baseline provenance destinations and included the full LGPL notice in the application license bundle.
- Recorded hosted-check and native first-import blockers without claiming a signed release.
- Bootstrapped the built extension before first Godot import, preventing the clean-checkout editor shutdown crash on Linux and macOS.
