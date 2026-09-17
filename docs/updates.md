# In-app updates

## Using the updater

In an installed, update-enabled macOS build, choose **Settings > Software updates...** or **RetroLife > Check for Updates...** in the macOS menu. Manual checking is always available even when scheduled checks are disabled. Sparkle presents release information, download progress, signature errors, and Install and Relaunch inside the application.

Automatic checks default to once a day. Automatic downloading and installation are a separate, initially disabled preference. Turning that preference on also enables checks. Turning checks off disables automatic downloading. Beta builds initially include the beta channel; stable builds do not. The channel can be changed in update settings, persists between launches, and never permits a downgrade. Sparkle also provides its standard skip, remind-later and cancellation actions.

The Rust emulation boundary acquires a native update barrier before starting a game. The barrier remains held through pause, stop requests and failed save attempts, and is released only after acknowledged stop/save or a failed initial startup without a live session. Update checks and installation cannot interrupt an active game. Conversely, a new game cannot start while an update session or committed installation is in progress. Return to the library and finish or cancel the update first.

Only the application bundle is replaced. The managed library, labels, preferences and saves remain in their existing user-data directories. Sparkle performs download, EdDSA verification, safe installation and relaunch. RetroLife does not implement shell-based app replacement or launch a downloaded executable itself.

Development, headless and Linux builds explicitly report that self-update is unavailable. An app running from a read-only disk image or App Translocation asks the user to move it to Applications. An unavailable updater never blocks ordinary development gameplay. A failed update keeps the existing application; the dialog provides retry/cancel rather than claiming a successful update.

## Trust and release identity

The production helper accepts only the application's signed bundle identity, a 32-byte public Ed25519 key, the fixed HTTPS feed below and ZIP downloads from this repository's versioned releases:

`https://raw.githubusercontent.com/lincolnaleixo/retrolife/updates/appcast.xml`

The EdDSA signature is mandatory even when a valid Apple signature exists. `SUVerifyUpdateBeforeExtraction` also requires verification before archive extraction. Sparkle verifies it against `SUPublicEDKey` embedded before code signing. The helper and every nested Sparkle component are signed inside-out using the same Developer ID as the application. No Library Validation exception, unsigned fallback or private key is included in the bundle.

`RLReleaseVersion` retains the human release tag without its leading `v`. The updater compares `CFBundleVersion` using Apple's a/b/fc prerelease suffixes: for example, `0.1.0-beta.10` becomes `0.1.0b10`, which is newer than `0.1.0b2` and older than final `0.1.0`. Release scripts reject invalid or out-of-range versions instead of guessing an ordering.

Sparkle 2.10.0 is fetched from its official release and verified against SHA-256 `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`. The verified SDK remains in `.cache/sparkle`, outside source history. `prepare-sparkle.py --archive <downloaded-package> --offline` supports disconnected preparation. Its complete license notice is copied into the release app.

## Publishing an update

Run the following on the trusted Apple Silicon release machine, from a reviewed clean commit, with the existing Developer ID and notarization configuration:

```sh
scripts/prepare-macos-release.sh 0.1.0-beta.3
```

Use the next unused version, not an existing immutable tag. The first run generates a Sparkle signing key in that machine's Keychain under account `io.github.lincolnaleixo.retrolife.sparkle`. Later runs reuse the same key. `SPARKLE_KEY_ACCOUNT` selects an existing account when necessary. The public key is injected into the bundle; the private key is never exported by this workflow. Back up the private key securely using Sparkle's documented key export procedure before relying on automatic distribution. Do not generate an unrelated new key for each release.

The script builds the helper, embeds the framework and public key, assigns the real release version, signs/notarizes/staples the app and creates `RetroLife-macos-arm64.zip`. It then verifies the app and ZIP metadata, signs the final ZIP with the Sparkle key, verifies that signature, and emits `retrolife-update.json`. Both files and their checksums accompany the usual corresponding-source, dependency, core-source and notice bundles. The optional DMG remains a manual first-install artifact; the updater uses the signed ZIP.

Upload all assets to a draft GitHub Release first, then publish it. Its tag must match the packaged version, and its prerelease flag must agree with the channel. The **Publish update feed** workflow validates the published metadata and actual GitHub asset identity/size/digest, then fast-forwards the isolated `updates` branch with a generated `appcast.xml`. It does not modify protected `main`, execute release binaries, or access signing credentials. Older releases without updater metadata are omitted. Deleted or unpublished releases are removed when the feed rebuilds. Manual workflow dispatch safely rebuilds the feed as well.

The generated `updates` branch is a distribution artifact, not application source or a second roadmap. Update implementation changes still require a changelog entry on the source branch. The feed is served over HTTPS; individual ZIP signatures are verified by clients. The publication job needs only repository `contents:write` and is never triggered by pull-request code.

The existing beta.1 and beta.2 cannot gain an updater retroactively. Beta.3 and later are updater-enabled; users install the first updater-enabled version once, after which later compatible signed releases are intended to install from within RetroLife. The first public signed-to-signed upgrade is still pending validation on the target Mac, as recorded in [the roadmap](../plan.md#execution-and-completion-rules).

## Verification boundaries

`test-updates.py` checks version ordering, channel separation, bundle trust configuration, escaped release notes, archive traversal/link rejection, GitHub asset matching and idempotent feed generation. The Godot updater smoke checks routed actions, settings, busy state, errors and narrow layout; it never downloads a real release.

`test-updater-native.py` compiles the production helper and an explicitly test-only host on Apple Silicon. It uses real Sparkle with a local feed, an ephemeral Ed25519 seed and disposable ad-hoc-signed bundles. The automated user driver replaces only UI interactions, not the download/verifier/installer. Test exceptions are compiled out of the production dylib. The test exercises no-update/downgrade/channel/OS filtering, network failures, untrusted download origins, tampered signatures and actual bundle replacement/relaunch. It must not publish its key, bundles or local feed.

These tests do not establish Developer ID/notarization acceptance of a new public release. Before announcing one, run the signed-to-signed upgrade on the target Mac, verify Gatekeeper after replacement, and confirm the user's library and saves persist. Existing published betas are not changed by merging this code.
