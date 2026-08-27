# Third-party boundaries

RetroLife uses external projects as build-time or runtime dependencies. Their licenses apply to their respective components.

- [Godot Engine](https://godotengine.org/) is licensed under the MIT License.
- [godot-rust](https://godot-rust.github.io/) provides the Rust GDExtension bindings and is licensed under the Mozilla Public License 2.0.
- Rust crate dependencies and their resolved versions are recorded in `Cargo.lock`.
- [CadQuery](https://github.com/CadQuery/cadquery) 2.8.0 is used as a build-time CAD library under the Apache License 2.0.
- [Open CASCADE Technology](https://github.com/Open-Cascade-SAS/OCCT) is used through CadQuery as a build-time geometry kernel under LGPL 2.1 with the OCCT additional exception. No CAD runtime library is bundled in the RetroLife frontend.

No emulator core, commercial game, ROM, BIOS, save, scraped media or third-party cartridge mesh is bundled in this repository.

The procedural assets under `frontend/godot-ui/assets/snes/m2` and `frontend/godot-ui/assets/snes/m2_2` carry separate CC0 notices and provenance records.

## External visual comparison references

M2.2 v4 records links to authentic cartridge photography, a public cartridge scan listing, public-domain cartridge photography, bottom photography and USD343833S. These sources are used for visual comparison only. No external mesh vertices, label artwork, textures or photograph pixels are copied into the generated CC0 asset package. See `frontend/design/m2-2-snes-v4-physical-comparison.md`.
