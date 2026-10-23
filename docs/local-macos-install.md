# Local macOS installation

Use `scripts/install-local-macos.py` for authorized local development updates to
the Applications copy. It is separate from the protected Developer ID and
notarization release workflow. Do not use production signing credentials for
development builds or run untrusted pull-request code on a signing host.

## Why the signing identity matters

macOS remembers privacy consent using the application's code signing designated
requirement. Ad-hoc signatures identify one exact build by its code hash. Changing
that build can therefore trigger the removable-volume prompt again, even when the
bundle identifier and Applications path stay the same. A certificate-backed
identity lets macOS recognize subsequent builds as the same application. See
[Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

Moving an existing ad-hoc installation to development signing can require one
new authorization. After that, installations must retain compatible designated
requirements. Do not reset TCC, change its database, disable security protections,
or request Full Disk Access to work around recurring prompts.

## Install a reviewed local export

Quit RetroLife normally first so active gameplay and saves can finish. The
exported app must have bundle identifier `io.github.lincolnaleixo.retrolife` and
`RLBuildChannel=local-development`. Finish all resource and Info.plist changes
before signing.

List the available development identities with `security find-identity -v -p
codesigning`. Select the intended **Apple Development** identity explicitly for
the first installation; pass its full certificate SHA-1 fingerprint:

```sh
python3 scripts/install-local-macos.py /path/to/RetroLife.app --identity CERTIFICATE_SHA1
```

The installer pins the identity in private local configuration. Subsequent
updates reuse it:

```sh
python3 scripts/install-local-macos.py /path/to/RetroLife.app
```

There is no ad-hoc fallback if the identity is unavailable. A renewed or changed
certificate must be reviewed for designated-requirement compatibility before
changing the local pin. Keep this configuration out of source control.

The installer stages outside cloud-synchronized folders, signs embedded code
inside-out, verifies the complete application, and checks continuity against an
existing certificate-signed copy. It preserves a rollback copy before replacing
application contents and verifies the installed result. It does not alter user
data, copy ROMs to internal storage, or modify privacy settings.

## Verify an update

```sh
python3 scripts/test-local-macos-install.py
codesign --verify --deep --strict /Applications/RetroLife.app
codesign --display -r- /Applications/RetroLife.app
```

The designated requirement must identify the bundle and signer, rather than only
the changing `cdhash`. On the target Mac, authorize the first migrated build if
macOS asks, relaunch it, then install a changed build with the pinned identity.
Confirm the external ROM library and gameplay open without a repeated prompt.
Automated signature checks alone do not prove a particular user's consent state.

Verified locally on 2026-10-23: migrated the installed ad-hoc app, then installed
a second build with changed signed metadata using the saved identity. The code
hashes differed, their designated requirements matched, and both versions loaded
the external-drive Super Mario World ROM. No repeated volume prompt was observed
after the second update. The journal and battery-save hashes were unchanged.
Fourteen portable installer tests cover identity selection, requirement syntax,
running apps (including symlink launches), unsafe inputs and rollback failures.
