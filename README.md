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
- **Journey** detects supported gameplay events automatically. Super Mario World (USA) awards four keepsakes for a Yoshi’s Island stage clear, a secret exit, a Koopaling castle and Bowser’s ending. There are no manual completion controls or time-based rewards. Menus, demos and pauses do not count as active play. Unsupported games hide the gameplay Journey column and toggle and do not appear in the Rewards collection. See [automatic achievements](docs/automatic-achievements.md) for supported ROM identity, event rules and legacy journal preservation. Rewards are local collectibles with no monetary value.
- Progress is stored locally in `journey.json`, checkpointed during play and flushed on clean stop. Closing the window waits for the emulator to finish saving. Keep backups of application data along with your ROM library.

Verification for this workspace is tracked in `plan.md`. A physical gamepad and audible output still need hands-on acceptance when those devices are available.


### Console gallery and game journals

The window uses integrated, borderless chrome. Drag the RetroLife wordmark area to move it; double-click that area or press F11 to toggle fullscreen. **Menu** also provides fullscreen, minimize and safe quit. The background is a static studio stage with no dotted overlay. [Local development installs](docs/local-macos-install.md) update `/Applications/RetroLife.app` using a pinned development signing identity, so launching the normal app opens the latest installed build and macOS can recognize subsequent updates. These are local builds, not notarized distribution releases.

The library opens on a carousel showing one 3D console at a time. Only systems with games in the library appear. Use the side buttons or Left/Right to change consoles, then click the console artwork (or press Enter/A) to browse games. With only one console, the side arrows are hidden. Use the top back arrow (or Escape outside a search) to return. Local ROM import and play remain SNES-only.

The carousel loads the selected model from `consoles/<console>/<console>-console.glb` in the linked local collection. Drag to rotate and scroll to zoom. Dragging or zooming does not open the collection. Missing models show an **Open collection** fallback; private console assets remain external.

The top **Box** action opens a matching local reproduction GLB with drag rotation, wheel zoom and Front/Back/Spine views. Models are read from the linked collection at `reproductions/<console>/<game>/box/<console>-<game>-box.glb`. The action is hidden when the matching model is unavailable.

Journey presentation profiles cover the seven current collection games, with optional colors and artwork. Automatic detection is currently implemented only for the verified Super Mario World (USA) revision. Its four supported event rewards use `journey/chapters/<milestone>.png` and `journey/rewards/05.png` through `08.png`, with SVG fallbacks; the hero is `journey/cover.png`. A bounded optional `journey/theme.json` supplies custom captions, colors and keepsake names. Pixel-art packs preserve crisp sprite edges and use integer enlargement for collectibles; each pack follows its game's visual style. Large illustrations stay colorful while locked; the card states whether the reward is earned. Packs load only after backend support is confirmed and stay cached during progress polling. Supported games without artwork use neutral event names and numbered placeholders. Unsupported games have no Journey controls or invented rewards. See [Journey art packs](docs/journey-art-packs.md). No game artwork is bundled or committed.

### Rewards and game presentation

**Rewards** in the top bar opens the collection across supported library games, with total XP, collected keepsakes and per-game filters. During supported gameplay, **Hide Journey** expands the game view; **Show Journey** restores the panel. This choice persists independently of game support. Games without detection use the full gameplay area. Drag the brand/status area to move the game window, or double-click it / press F11 for fullscreen. The startup splash uses original RetroLife branding.

Game selection can show a bespoke background, description, year, genre, player count and a local preview video. **Menu → Game media · ScreenScraper** configures an explicit lookup for the selected game. Developer credentials and optional user credentials stay in the current session and are cleared when the panel closes. No request runs just from browsing the library. Games without a presentation pack keep their neutral background. Optional music comes from each game's local pack, starts disabled and has its own volume; it stops for gameplay and video previews.

See [game presentation and ScreenScraper](docs/game-presentation.md) for configuration, offline imports, provenance, supported video/audio formats and verification limits. ScreenScraper MP4 gameplay previews open in the system player; local Theora OGV previews play inside RetroLife. The explicit local converter can prepare an MP4 for inline playback when a Theora-enabled ffmpeg is available. Selection music is imported locally, with no claimed ScreenScraper soundtrack support. No downloaded game media or account credentials are bundled with the app.

### Settings while playing

Choose **Settings** in the gameplay header, press **F9**, or choose **Game settings** on the pause screen. RetroLife pauses the game and audio before opening the settings hub. **Controllers & keyboard** opens the existing 3D controller setup with live button mapping; **Display shaders** opens the SNES frame preview; **RetroLife preferences** opens the library's existing motion and rendering options. Closing a child panel returns to the hub without resuming. **Done**, Escape from the hub, or F9 restores the play/pause state from before you opened settings.

The hub also provides saved gameplay volume (including mute), fullscreen and the Journey toggle for supported games. These are the available frontend/emulator presentation settings; the UI does not invent unsupported core options. Held inputs are released when entering settings and must be released physically before gameplay input resumes. F5–F9 and F11 are reserved for Quick save, Saved moments, Quick load, display shaders, settings and fullscreen; new keyboard mappings reject those keys, while older saved conflicts stay intact and are labeled for remapping. If pausing fails, settings stay closed; if resuming fails, the ordinary paused controls remain available. Exiting the application from any settings panel keeps the game paused while the normal save-and-stop flow completes.

### Save and load states

During a SNES game, choose **Saves** or press **F6** to open **Saved moments**. Six manual slots show the saved frame and date; Quick save has its own slot. **F5** opens Quick save, and **F7** opens Quick load. Replacing a saved slot or loading a state asks for confirmation. Every load first preserves the current point in **Recovery**, which can be loaded to undo an accidental jump. The game stays paused while browsing or working, and returns to its previous play/pause state when you close the browser.

States remain separate from the normal cartridge save. They are local and compatible only with the matching ROM and emulator build/options. Loading resets achievement transition evidence without removing earned rewards. See [save states](docs/save-states.md) for persistence, recovery and compatibility details.

### Super Nintendo display shaders

During a SNES game, choose **Shaders** in the integrated header or press **F8**. Compare Original, Smooth, Scanlines and CRT on the current frame, adjust intensity, then choose Done (or Escape). The game pauses during the preview and returns to its previous play/pause state when the panel closes. Your display preference is saved for Super Nintendo. Original keeps the unfiltered nearest-neighbor image. Display effects do not change the emulated game, saves, input mapping or achievement detection.
