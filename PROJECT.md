# RetroLife architecture

RetroLife is a frontend and launcher, not an emulator implementation.

## Boundaries

- `frontend/godot-ui/` owns scenes, interaction, navigation, animation and presentation.
- `frontend/godot-bridge/` owns Godot-facing DTO conversion and asynchronous dispatch.
- `frontend/launch-bridge/` owns the native launch boundary.
- `crates/retrolife-core/` owns platform-independent domain and systems logic.
- `crates/retrolife-launch-fixture/` provides a deterministic launch integration fixture.

The core does not depend on Godot types. The bridge is intentionally thin, and expensive work must not block the Godot render thread.

## Product direction

The active reference experience is SNES-first and uses physical media as the primary interaction metaphor. The frontend must remain replaceable without rewriting the domain model. Emulator execution is delegated to maintained external runtimes supplied by the user.
