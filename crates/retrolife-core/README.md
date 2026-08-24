# RetroLife Core

`retrolife-core` is the active platform-independent Rust domain core for the new RetroLife frontend.

The first migrated behavior is the display settings contract, adapted from the historical `tv_settings` implementation. It preserves schema migration, validation, canonical JSON, and defaults while generalizing the model for macOS, Steam Deck, and living-room targets.

This crate must not depend on Godot types. Godot-specific conversion belongs in `frontend/godot-bridge/`.

## Current API

- `default_display_settings()`
- `default_display_settings_json()`
- `normalize_display_settings_json()`
- the `DisplaySettings` model and related enums

## Verification

From the repository root:

```sh
rtk cargo test -p retrolife-core
```
