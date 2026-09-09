# RetroLife

A retro game library built with Rust and Godot, with SNES gameplay inside the application window.

**Status:** first playable release in development. No signed release is available yet. See [the roadmap](plan.md) and [changelog](CHANGELOG.md) for verified progress and remaining work.

The first target is macOS 13+ on Apple Silicon. Linux builds support development checks; Linux distribution is a later milestone. Import your own `.sfc` or `.smc` files: RetroLife copies them into its local library and keeps local battery-backed saves. Games and artwork are not bundled.

## Development

Install Rust through rustup (the toolchain file pins the version), Godot 4.7.2, Python 3, Git and a C/C++ toolchain. On macOS, install Xcode Command Line Tools.

```sh
scripts/build-core.sh
scripts/build.sh
godot --path frontend/godot-ui
scripts/check.sh
```

Set `GODOT` when the executable has another name. Dependencies are pinned in Cargo.lock and the core build script. Consult [architecture](docs/architecture.md), [contribution guidance](CONTRIBUTING.md), and [release instructions](docs/releases.md).

Original application code: **AGPL-3.0-only**. See [third-party notices](THIRD_PARTY_NOTICES.md). The separate [3D cartridge collection](https://github.com/lincolnaleixo/retro-cartridge-models) retains its own licenses and is planned for a future library interface.
