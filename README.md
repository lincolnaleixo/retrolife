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

Original application code: **AGPL-3.0-only**. See [third-party notices](THIRD_PARTY_NOTICES.md). The separate [Retro 3D Library](https://github.com/lincolnaleixo/retro-3d-library) retains its independent CC BY-NC-ND 4.0 license and version history. No game artwork is relicensed as application code.

## Application updates

Updater-enabled signed macOS builds provide **Settings > Software updates...** and **Check for Updates...** in the macOS application menu. Scheduled checks, optional automatic installation and stable/beta channels use signed Sparkle updates without replacing your library or saves. Beta.3 and later are updater-enabled: install one of them manually once, after which later releases are expected to arrive inside the app — the first public signed-to-signed upgrade is still pending validation on the target Mac. The older beta.1 and beta.2 downloads predate this feature. See the [updater guide](docs/updates.md).

## Library workspace and personal journey

- **Play game** starts the selected game directly. **Controllers** opens visual SNES button mapping; **Storage & assets** shows the active ROM folder and local artwork collection.
- Choose a folder on an external drive to copy the managed collection. RetroLife verifies content identities, preserves display titles and leaves originals intact. New imports use `snes/` inside the selected root. Existing `roms/` libraries remain readable. Reconnect an offline drive or select an existing library; RetroLife does not silently import into the internal disk instead.
- Battery saves remain in platform application data, keyed by the same content identity, independently of ROM storage.
- Link a local Retro 3D Library results folder containing `controllers/`, `consoles/` and `reproductions/`. The SNES controller, console render and matching Super Mario World reproduction are loaded from that folder. No private assets, artwork, ROMs or personal configuration are bundled or uploaded. Missing assets keep the neutral presentation available.
- In **Controllers**, select gamepad or keyboard bindings, click a target button or use **Guided setup**. The SNES model highlights the target. Escape, timeout and device disconnection restore unfinished mappings; completed mappings persist. Pause remains reserved. Gamepad bindings apply to any connected standard gamepad. SNES is still the only playable system.
- **Journey** beside gameplay tracks four session-time milestones (1, 10, 30 and 60 minutes), four explicitly self-reported personal challenges, XP, levels and eight collectible rewards per game. Paused frames do not count. Confirming a challenge twice does not duplicate XP; correcting a checkbox removes its reward. Levels use combined XP across games. These are local personal rewards, with no purchases or monetary value. Stage clears and secrets are not automatically detected.
- Progress is stored locally in `journey.json`, checkpointed during play and flushed on clean stop. Closing the window waits for the emulator to finish saving. Keep backups of application data along with your ROM library.

Verification for this workspace is tracked in `plan.md`. A physical gamepad and audible output still need hands-on acceptance when those devices are available.


### Console gallery and game journals

The library opens on the console gallery. Choose a system to browse its games and use **Consoles** (or Escape outside a search) to return. Empty consoles do not imply emulator support; local ROM import and play remain SNES-only.

Console cards display interactive models from `consoles/<console>/<console>-console.glb` in the linked local collection. Drag to rotate and double-click to reset; the wheel scrolls the gallery. Choose **Open collection** to enter the games. Missing models show a clear hint; private console assets remain external.

**Inspect box in 3D** opens a matching local reproduction GLB with drag rotation, wheel zoom and Front/Back/Spine views. Models are read from the linked collection at `reproductions/<console>/<game>/box/<console>-<game>-box.glb`. Missing models disable inspection rather than substituting another game.

Journey presentation profiles cover the seven current collection games. They customize chapter copy, four personal goals, eight reward names, colors and collectible stamps. Progress still uses stable milestone IDs, so changing presentation preserves existing XP and rewards. Game-specific headers are read from `reproductions/<console>/<game>/journey/cover.png`, falling back to the local box render. Unknown games receive a neutral journal. No game artwork is bundled or committed. Story goals remain self-reported, not emulator achievement detection.
