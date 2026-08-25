# Third-party boundaries

RetroLife uses external projects as build-time or runtime dependencies. Their licenses apply to their respective components.

- [Godot Engine](https://godotengine.org/) is licensed under the MIT License.
- [godot-rust](https://godot-rust.github.io/) provides the Rust GDExtension bindings and is licensed under the Mozilla Public License 2.0.
- Rust crate dependencies and their resolved versions are recorded in `Cargo.lock`.

No emulator core, commercial game, ROM, BIOS, save, scraped media or third-party cartridge mesh is bundled in this repository.

The procedural assets under `frontend/godot-ui/assets/snes/m2` and `frontend/godot-ui/assets/snes/m2_2` carry separate CC0 notices and provenance records.

## External visual comparison references

M2.2 v3 records links to an authentic-cartridge scan, public cartridge photography, bottom photography and USD343833S. These sources are used for visual comparison only. No external mesh vertices, textures or photographs are copied into the generated CC0 asset package. See `frontend/design/m2-2-snes-v3-physical-comparison.md`.
