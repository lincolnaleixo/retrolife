# Live ROM folders

Choose a ROM root in Storage settings. Add SNES games inside its `snes` folder using Finder or another file manager. RetroLife discovers `.sfc`, `.smc` and single-game `.zip` files at startup and polls while browsing the collection. Changes normally appear within four seconds. Scans run on a Rust worker; playback is not interrupted and updates are applied after returning to the library.

Names stay as chosen by the user. A SHA-256 of the uncompressed ROM identifies the game, so renaming or changing between raw and ZIP storage preserves its save/progress identity. Removing a file removes it from the collection, without removing battery saves, save states or Journey records. A different ROM revision has a different identity and is not silently linked to another revision's saves.

ZIPs remain intact. At launch the one SNES image is verified and written to `.rom-cache` outside the scanned console folder. Cached images do not reappear as games after an archive is removed. Archives are limited to 32 MiB compressed and uncompressed, 128 members and exactly one SNES image. Stored and Deflate compression are supported. Ambiguous, incomplete, unsafe and unsupported archives are skipped and retried on subsequent scans. Symlink console folders are rejected; symlink files are ignored. Files are never renamed, removed or restored by reconciliation.

The library index contains relative paths and is updated atomically. An unavailable removable volume does not get recreated on the internal drive. Scanning does not configure cloud synchronization or synchronize save data between machines.
