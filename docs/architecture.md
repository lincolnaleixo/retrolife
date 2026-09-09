# Architecture

Godot owns the library interface, input mapping, the gameplay texture and audio playback. A Rust GDExtension connects those surfaces to the domain and emulation crates.

`retrolife-library` owns copied local game files and their content identities. `retrolife-core` preserves catalog and display contracts. `retrolife-emulation` owns a single native libretro session on its worker thread. Only owned data crosses the bridge; native core pointers never escape it.

Imports live under Godot's application data directory. Originals are untouched. Battery saves use game content identity and atomic replacement. Failures remain visible instead of silently replacing valid saves.

The core is bundled at a pinned revision. No remote catalog, server, account or runtime core download is needed. Archive content is not active code. Future 3D assets will be resolved through a versioned external collection rather than coupled to emulation.

The first release accepts the pinned memory-loading SNES core only. Core calls are in-process and must return: a native core hang can block shutdown, and the application cannot safely unload a library that is still executing. Process isolation is a future hardening option, not a guarantee of this release.
