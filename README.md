# RetroLife

A retro game library built with Rust and Godot, with SNES gameplay inside the application window.

**Status:** signed testing betas are published automatically in [GitHub Releases](https://github.com/lincolnaleixo/retrolife/releases); the latest beta contains the cartridge-first library and the in-app updater. Hands-on gameplay, sound, controller and visual acceptance remain pending, so no beta claims the completed v0.1.0 milestone. See [the roadmap](plan.md) and [changelog](CHANGELOG.md) for verified progress and remaining work, and the [executor guide](docs/executor-guide.md) to contribute to the roadmap.

The first target is macOS 13+ on Apple Silicon. Linux builds support development checks; Linux distribution is a later milestone. Import your own `.sfc` or `.smc` files: RetroLife copies them into its local library and keeps local battery-backed saves. Games and game artwork are not bundled.

## Cartridge library

Browse a physical 3D cartridge collection with keyboard, controller or mouse. The selected SNES cartridge is centered, nearby games recede in perspective, and search/import controls stay compact. Choose a local PNG label in game details, or keep an original neutral title label; matching games can also show their approved label, downloaded on request from the public cartridge collection and verified locally before use. Settings offers reduced motion, low-power rendering, a text alternative and the approved-label download switch. The library remembers selections across filters, details and gameplay.

Read the [interface and artwork guide](docs/cartridge-library.md) for controls, offline asset staging, resource budgets and verification. The pinned neutral model is fetched at build time; installed application browsing does not need a network connection.

## Development

Install Rust through rustup (the toolchain file pins the version), Godot 4.7.2, Python 3, Git and a C/C++ toolchain. On macOS, install Xcode Command Line Tools.

```sh
scripts/build-core.sh
scripts/build.sh
godot --path frontend/godot-ui
scripts/check.sh
```

Set `GODOT` when the executable has another name. Dependencies are pinned in Cargo.lock and the core build script. The model package and per-file checksums are pinned in `assets/cartridges.lock.json`; large creative files are staged outside Git history. Consult [architecture](docs/architecture.md), [contribution guidance](CONTRIBUTING.md), and [release instructions](docs/releases.md).

Original application code: **AGPL-3.0-only**. See [third-party notices](THIRD_PARTY_NOTICES.md). The separate [3D cartridge collection](https://github.com/lincolnaleixo/retro-cartridge-models) retains its independent CC BY-NC-ND 4.0 license and version history. No game artwork is relicensed as application code.

## Application updates

Updater-enabled signed macOS builds provide **Settings > Software updates...** and **Check for Updates...** in the macOS application menu. Scheduled checks, optional automatic installation and stable/beta channels use signed Sparkle updates without replacing your library or saves. Beta.3 and later are updater-enabled: install one of them manually once, after which later releases are expected to arrive inside the app — the first public signed-to-signed upgrade is still pending validation on the target Mac. The older beta.1 and beta.2 downloads predate this feature. See the [updater guide](docs/updates.md).
