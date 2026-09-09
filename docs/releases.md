# Releases

Release `v0.1.0` remains pending until the native acceptance checks pass. Do not publish an unsigned fallback or mark a build playable based only on compilation.

CI runs on hosted runners. Signing is a separate private Apple Silicon operation; never register the signing machine as a runner that executes public pull requests. Verify Developer ID Application access and a working notary Keychain profile there before release preparation.

The application uses bundle identifier `io.github.lincolnaleixo.retrolife`, separate from previous applications. Pin Godot 4.7.2, Rust 1.98.1 and the core commit. Install matching Godot export templates on the signing machine.

For a reviewed clean commit, run all checks, build the release bridge and core, and export the macOS application. Provide `SIGNING_IDENTITY` and `NOTARY_PROFILE` through the private signing environment. Never store their resolved credentials in this repository or logs.

The signing script signs nested dylibs before the application, notarizes a temporary ZIP, staples the application and recreates the final ZIP. It rejects non-Apple-Silicon hosts and unsigned output. Its output is local; publication follows verification of the downloaded package and sustained gameplay, input, sound and save restoration.

Attach the signed ZIP, checksums, exact source archive, dependency source/license bundles, and core-source archive to an immutable `v0.1.0` prerelease. Extract notes from the dated changelog. Do not include `.cache`, private metadata, archive references, or game files. Automatic updates are outside this release.
