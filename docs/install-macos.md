# Install RetroLife on a Mac

Use an updater-enabled, signed release for everyday play. The current target is
Apple Silicon with macOS 13 or later. Local development exports are a separate
testing channel and cannot acquire the updater by changing a preference.

## First installation or development-build migration

1. Download the newest compatible DMG from
   [RetroLife Releases](https://github.com/lincolnaleixo/retrolife/releases).
2. If RetroLife is already running, save and quit normally. Keep the previous
   application until the replacement has been verified. Do not remove its
   application data, ROM folder, artwork or saves.
3. Open the DMG and copy RetroLife to Applications. Open that Applications copy.
   Running directly from the disk image is not an update-capable installation.
4. Open Settings > Software updates and check for updates. During the beta period,
   keep the beta channel enabled to receive newer testing releases.

The first move from development signing to distribution signing can require a
new macOS file-access authorization. Do not reset privacy settings or grant broad
disk access as a workaround. Subsequent distribution builds use the same app
identity and signed update channel.

## Private collection and storage

The public app does not include ROMs, commercial game artwork or the owner's
private 3D library. An owner installation can copy its curated, versioned asset
pack separately and select that pack in Storage & assets. Use a location outside
RetroLife.app so an application replacement cannot remove it.

Configure a ROM folder that exists on the destination Mac. An external drive's
path on another computer is not automatically available locally. Do not copy a
whole development checkout, build cache or old rendering audits to install the
collection. Do not overwrite the destination Mac's library or progress with
another Mac's preferences and saves. Cross-device save synchronization is not
part of the updater.

## Later updates

Use Settings > Software updates or the native Check for Updates menu item. The
updater verifies the signed download and offers Install and Relaunch. Automatic
checks and automatic installation are separate preferences. Update installation
must wait until active gameplay and save work have finished.

For maintainers, every delivered version must correspond to an immutable release
and its verified appcast entry. Follow the
[automatic release pipeline](automatic-releases.md); do not replace an installed
release with a development export and claim it will update normally.

## Verification record

Record the installed release version, source commit, signature/Gatekeeper
verification, updater availability and outcome on the destination Mac. A build
or a successful download alone does not prove an installed update works. Keep
device addresses, account names, private paths and credentials out of public
evidence.
