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

- Click the selected cartridge, or press Enter/A, to play. The top **Menu** contains **Controllers**, **Storage & assets**, import and display settings. **Details** and **Box** are contextual actions beside it.
- Choose a folder on an external drive to copy the managed collection. RetroLife verifies content identities, preserves display titles and leaves originals intact. New imports use `snes/` inside the selected root. Existing `roms/` libraries remain readable. Reconnect an offline drive or select an existing library; RetroLife does not silently import into the internal disk instead.
- Battery saves remain in platform application data, keyed by the same content identity, independently of ROM storage.
- Link a local Retro 3D Library results folder containing `controllers/`, `consoles/` and `reproductions/`. The SNES controller, console render and matching Super Mario World reproduction are loaded from that folder. No private assets, artwork, ROMs or personal configuration are bundled or uploaded. Missing assets keep the neutral presentation available.
- In **Controllers**, select gamepad or keyboard bindings, click a target button or use **Guided setup**. The SNES model highlights the target. Escape, timeout and device disconnection restore unfinished mappings; completed mappings persist. Pause remains reserved. Gamepad bindings apply to any connected standard gamepad. SNES is still the only playable system.
- **Journey** detects supported gameplay events automatically. Super Mario World (USA) awards four keepsakes for a Yoshi’s Island stage clear, a secret exit, a Koopaling castle and Bowser’s ending. There are no manual completion controls or time-based rewards. Menus, demos and pauses do not count as active play. Unsupported games show a clear unavailable state. See [automatic achievements](docs/automatic-achievements.md) for supported ROM identity, event rules and legacy journal preservation. Rewards are local collectibles with no monetary value.
- Progress is stored locally in `journey.json`, checkpointed during play and flushed on clean stop. Closing the window waits for the emulator to finish saving. Keep backups of application data along with your ROM library.

Verification for this workspace is tracked in `plan.md`. A physical gamepad and audible output still need hands-on acceptance when those devices are available.


### Console gallery and game journals

The window uses integrated, borderless chrome. Drag the RetroLife wordmark area to move it; double-click that area or press F11 to toggle fullscreen. **Menu** also provides fullscreen, minimize and safe quit. The background is a static studio stage with no dotted overlay. [Local development installs](docs/local-macos-install.md) update `/Applications/RetroLife.app` using a pinned development signing identity, so launching the normal app opens the latest installed build and macOS can recognize subsequent updates. These are local builds, not notarized distribution releases.

The library opens on a carousel showing one 3D console at a time. Only systems with games in the library appear. Use the side buttons or Left/Right to change consoles, then click the console artwork (or press Enter/A) to browse games. With only one console, the side arrows are hidden. Use the top back arrow (or Escape outside a search) to return. Local ROM import and play remain SNES-only.

The carousel loads the selected model from `consoles/<console>/<console>-console.glb` in the linked local collection. Drag to rotate and scroll to zoom. Dragging or zooming does not open the collection. Missing models show an **Open collection** fallback; private console assets remain external.

The top **Box** action opens a matching local reproduction GLB with drag rotation, wheel zoom and Front/Back/Spine views. Models are read from the linked collection at `reproductions/<console>/<game>/box/<console>-<game>-box.glb`. The action is hidden when the matching model is unavailable.

Journey presentation profiles cover the seven current collection games, with optional colors and artwork. Automatic detection is currently implemented only for the verified Super Mario World (USA) revision. Its four supported event rewards use `journey/chapters/<milestone>.svg` and `journey/rewards/05.svg` through `08.svg`; the hero is `journey/cover.png`. Images load once per selection. Missing artwork stays absent and never falls back to another game. Unsupported games have no invented objectives or rewards. No game artwork is bundled or committed.

### Rewards and game presentation

**Rewards** in the top bar opens the collection across all library games, with total XP, collected keepsakes and per-game filters. During gameplay, **Hide Journey** expands the game view; **Show Journey** restores the panel. This choice persists. Drag the brand/status area to move the game window, or double-click it / press F11 for fullscreen. The startup splash uses original RetroLife branding.

Game selection can show a bespoke background, description, year, genre, player count and a local preview video. **Menu → Game media · ScreenScraper** configures an explicit lookup for the selected game. Developer credentials and optional user credentials stay in the current session and are cleared when the panel closes. No request runs just from browsing the library. Games without a presentation pack keep their neutral background.

See [game presentation and ScreenScraper](docs/game-presentation.md) for configuration, offline imports, provenance, supported video formats and verification limits. ScreenScraper MP4 previews open in the system player; local Theora OGV previews play inside RetroLife. No downloaded game media or account credentials are bundled with the app.
