# Automatic signed macOS beta releases

## Trigger and boundaries

Every push to `main` starts **Automatic macOS beta release**. One push creates at most one release for its final source commit, including all earlier commits in that push. Local commits that have not been pushed cannot trigger GitHub. Branches, tags, forks and PRs do not receive production signing credentials or publish releases. Use the workflow's **Run workflow** button on main to retry; there is no arbitrary source/branch/version input.

Runs are serialized using `queue: max`, allowing up to 100 queued runs rather than canceling pending releases. The workflow builds the exact triggering SHA, never whichever commit main points to later. A complete release for that SHA is reused on a full rerun and only its feed is refreshed. An older queued source is refused when a newer or divergent source has already been published, preventing a source rollback. Failed tests, missing credentials, signature/notarization failures and asset mismatches never produce an unsigned substitute.

Versions are selected from existing tags and releases, including drafts. Beta.2 is followed by beta.3; beta.10 is newer than beta.9. The Apple prerelease suffix limit is handled by moving beta.255 to the next patch's beta.1. Published tags and assets are never overwritten. `assets/release-policy.json` defines the minimum base series; stable releases are not generated automatically.

## One-time protected configuration

Create an environment named `macos-release` in the repository's Settings > Environments. Set **Deployment branches and tags > Selected branches and tags > Branch > main** as its only allowed deployment rule. Do not allow PR refs, tags, wildcards or other branches. Existing approval rules may remain; when configured, each release waits for them. Store signing values as environment secrets, not source files or repository-wide secrets.

| Environment secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64 of the specifically exported Developer ID Application identity, including its private key. |
| `MACOS_CERTIFICATE_PASSWORD` | Password protecting that P12. |
| `APPLE_ID` | Apple account authorized to notarize for the team. |
| `APPLE_APP_PASSWORD` | Apple app-specific password, not the normal login password. |
| `SPARKLE_PRIVATE_KEY` | Sparkle's private-key export from the persistent signing account. Reuse the same key on every build. |

| Environment variable | Value |
| --- | --- |
| `APPLE_TEAM_ID` | The Apple Developer team identifier, 10 characters. |
| `SPARKLE_PUBLIC_KEY` | Canonical base64 public key from that same Sparkle account. |

The certificate and notary credentials from previous manually signed betas are not automatically present on GitHub's hosted runners. Never paste a private key/password into an issue, PR, chat or workflow log. Do not generate a new unrelated Sparkle signing key for every release. A missing key is a configuration failure, not permission to weaken verification.

A helper is provided for a one-time interactive setup from the trusted Mac with authenticated GitHub CLI and repository administration permission:

```sh
python3 scripts/configure-release-environment.py /path/to/DeveloperID.p12 \
  --team-id YOURTEAMID --apple-id your-apple-account
```

It verifies the main-only environment scope, prompts for passwords without echo, exports only the selected Sparkle account to a temporary private file, sends secret values through `gh` standard input, sets the two public variables and starts the main workflow. Existing environment reviewer rules are not deliberately removed. Broader preexisting deployment rules cause setup to stop rather than deleting them silently.

Only for the first setup when no persistent Sparkle key exists, add `--initialize-sparkle-key`. An existing account is reused. Back up that key securely according to Sparkle's procedure; GitHub does not let you retrieve stored secret plaintext later. Export the specific Developer ID identity with Keychain Access, not your complete Keychain. The helper does not enumerate or export unrelated private identities.

The release preflight exposes only missing configuration names. It does not read or print the private values. Once configuration is complete, retry the complete workflow from main.

## Pipeline and signing isolation

1. Plan the version from the exact source and reserved release history.
2. Validate configuration presence, then build on a fresh Apple Silicon runner with only the public key. Run Rust, real-core, Godot, asset, updater, publication, vulnerability and secret checks. Verify the official Godot engine and export templates before use.
3. Transfer the exact same-run unsigned artifact with a verified SHA-256. A separate protected macOS job imports the existing Developer ID and Sparkle keys into a temporary Keychain, notarizes/staples the app and disk image, signs the updater ZIP and verifies its signature. Cleanup runs on exceptions; hosted runners are disposable if a hard cancellation interrupts cleanup.
4. Delete the temporary Keychain/private files before launching the signed app. Check the real exported application reports the correct release version and `available: true` through the normal production updater. The probe does not open a ROM library, import a game or bypass signatures. Headless/ad-hoc tests must remain update-disabled.
5. Publish only an exact public asset allowlist using a separate write-token job without Apple/Sparkle secrets. Upload to a draft, verify GitHub's asset sizes and SHA-256 digests, then publish the prerelease.
6. Explicitly rebuild and verify the public HTTPS appcast. A release created by `GITHUB_TOKEN` does not trigger a second release-event workflow, so this step must not depend on that event.

Source archives include the build workflows. Public assets comprise the signed DMG and ZIP, `retrolife-update.json`, application/Rust dependency/core source archives, creative-asset lock, notices, release notes, build provenance and a complete `SHA256SUMS`. Only source-approved resources are bundled, never ROMs, user labels or personal saves. The temporary unsigned artifact is an internal build input with one-day retention, not a user testing release.

## Verification and recovery

`test-release-automation.py` covers version transitions, main-only context, missing configuration, asset allowlisting, source/hash binding, upload failure and overwrite refusal. `test-release-packaging.py` builds a disposable ad-hoc copy of the actual export, verifies its embedded components, source/notices and Godot probe, and confirms it cannot enable unsigned/headless updates. It does not substitute for Developer ID/notarization checks. Existing real-Sparkle native tests remain mandatory in the release build.

A signing failure leaves no public candidate. A partial upload remains a draft and is not offered to users; rerun the complete workflow to allocate a new unused version. Never use force-push or upload clobber to replace released bytes. If publication succeeded but feed refresh failed, a full rerun detects the existing release and refreshes only the feed. Source secrets are never an artifact.

The first updater-enabled signed build must be installed manually once because older downloads contain no updater. Afterwards, compatible signed releases appear inside RetroLife. Automatic installation remains opt-in and never interrupts an active game/save. Hands-on audio/controller acceptance, sustained performance and signed-to-signed upgrades with real existing saves are explicitly pending beta acceptance, not inferred from compilation.

## References

- GitHub workflow concurrency: https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency
- GitHub environment protection: https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments
- GitHub workflow triggering and token recursion: https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-when-your-workflow-runs/triggering-a-workflow
- Sparkle signing keys and publication: https://sparkle-project.org/documentation/
