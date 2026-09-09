# Releases

Release `v0.1.0` remains pending until the native acceptance checks pass. Do not publish an unsigned fallback or mark a build playable based only on compilation.

CI runs on hosted runners. Signing is a separate private Apple Silicon operation; never register the signing machine as a runner that executes public pull requests. Verify Developer ID Application access and a working notary Keychain profile there before release preparation.

The application uses bundle identifier `io.github.lincolnaleixo.retrolife`, separate from previous applications. Pin Godot 4.7.2, Rust 1.98.1 and the core commit. Install matching Godot export templates on the signing machine.

For a reviewed clean commit, run all checks, build the release bridge and core, and export the macOS application. Provide `SIGNING_IDENTITY` and `NOTARY_PROFILE` through the private signing environment. Never store their resolved credentials in this repository or logs.

The signing script signs nested dylibs before the application, notarizes a temporary ZIP, staples the application and recreates the final ZIP. It rejects non-Apple-Silicon hosts and unsigned output. Its output is local; publication follows verification of the downloaded package and sustained gameplay, input, sound and save restoration.

Attach the signed ZIP, checksums, exact source archive, dependency source/license bundles, and core-source archive to an immutable `v0.1.0` prerelease. Extract notes from the dated changelog. Do not include `.cache`, private metadata, archive references, or game files. Automatic updates are outside this release.

The exported release template does not run the editor-only `--script` smokes. Use `--headless --quit-after 5` for packaged startup, and keep the full script-driven integration checks in the editor build. Packaged startup alone does not verify physical controls or audible output.

## Verifying bundled Rust sources

The application archive contains the exact source revision. Extract the Rust dependency archive into its `dist/` directory, then install the supplied Cargo source configuration:

```sh
tar -xzf retrolife-source.tar.gz
mkdir -p retrolife/dist retrolife/.cargo
tar -xzf retrolife-rust-dependencies.tar.gz -C retrolife/dist
cp retrolife/dist/vendor-config.toml retrolife/.cargo/config.toml
cd retrolife
cargo test --workspace --locked --offline
```

This verifies the Rust sources and dependencies; it does not build or export a runnable app. Install the pinned Rust toolchain and a native C/C++ compiler/linker first (Xcode Command Line Tools on macOS). The separate core-source archive contains the exact bsnes-jg revision; Godot and its matching export templates are independent build prerequisites. The generated test ROM remains reproducible from its original source script and is not bundled with the app.
