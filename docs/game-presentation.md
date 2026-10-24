# Local game presentation and ScreenScraper

RetroLife can show a game's description, release year, developer, publisher, genre, player count, background and preview video from a local presentation pack. A pack can also provide music for that game's selection screen. Changing games reads local data only. Downloading metadata or media always requires an explicit action.

## ScreenScraper setup inside RetroLife

1. Open a console, select a game, then choose **Game media · ScreenScraper** from the header menu.
2. Enter the **developer ID** and **developer password** approved for your ScreenScraper application. A normal user account does not replace developer credentials.
3. Optionally enter your separate **user login** and **user password**, together. This associates the request with that account and its service limits.
4. Search for the game, inspect the titles, release years and ScreenScraper game IDs, and select the correct match. Searches are scoped to the selected console. RetroLife does not upload ROM files or hashes.
5. Choose whether to download a background and an MP4 video, then select **Save selected game's media**. Background priority is fanart, screenshot, then title screen. Video priority is `video-normalized`, then `video`; advertised unsupported formats or videos over 128 MiB are skipped. Metadata prefers US/world titles and an English synopsis.

ScreenScraper describes these videos as gameplay captures; a preview is not necessarily a promotional trailer. The API documents MP4 delivery and a `NOMEDIA` response when an advertised file is unavailable. RetroLife retains any existing media in that case and saves the available metadata. The published API does not document a separate game soundtrack endpoint, so selection music is imported locally instead of scraped. [ScreenScraper API v2](https://www.screenscraper.fr/webapi2.php)

The fields are session-only. Closing the window cancels an in-flight request and clears both passwords and IDs from the form. Nothing is saved to preferences, logs, the repository or the exported app. RetroLife does not read other applications' settings or the Keychain. These controls clear application references; they are not a guarantee of cryptographic memory erasure by the operating system.

An approved developer account still needs its actual credentials entered before a live request can succeed. The integration has offline fixture coverage; it has not been authenticated against a live account during development.

Requests use the fixed HTTPS ScreenScraper API host. Raw responses, user-account objects and credential-bearing media URLs are discarded. Media requests are reconstructed from allowlisted media types and region identifiers. Redirects are rejected so credentials are never forwarded to a different host. If the service uses a CDN redirect, the current client reports that limitation and retains the existing presentation. Rate limits and quota errors are reported without automatic retries. One request runs at a time.

## Pack location and format

Packs live outside the app, in the linked local 3D collection:

```text
reproductions/<system>/<game-slug>/presentation/
  metadata.json
  background.png
  preview.ogv
  theme.ogg
```

Supported systems are `nes`, `snes`, `mega-drive`, `playstation-1`, `nintendo-64`, `game-boy` and `game-boy-advance`. The slug uses lowercase letters, digits and hyphens. `game.system` and `game.slug` must match the selected game exactly; assets are never borrowed from an unrelated game.

```json
{
  "schemaVersion": 1,
  "game": {
    "system": "snes",
    "slug": "example-game",
    "title": "Example Game"
  },
  "description": "An original, concise description of this particular game.",
  "developer": "Example Studio",
  "publisher": "Example Publisher",
  "year": "1991",
  "genre": "Platform",
  "players": "1-2",
  "media": {
    "background": {
      "path": "background.png",
      "source": "Provider or original artist attribution"
    },
    "video": {
      "path": "preview.ogv",
      "source": "Provider or original recording attribution"
    },
    "music": {
      "path": "theme.ogg",
      "source": "Local recording or licensed music attribution"
    }
  },
  "source": {
    "provider": "Local metadata",
    "retrievedAt": "2026-10-23T10:00:00Z",
    "url": "https://example.org/game"
  }
}
```

All non-identity fields are optional. `source.provider` accepts any plain attribution, including Nintendo, ScreenScraper or an original author. ScreenScraper adds numeric `gameId` and `systemId` strings. Metadata is plain text, not executable markup. Source URL queries and fragments are stripped to prevent accidentally storing API credentials.

Each media entry may include a `sha256` value of 64 lowercase hexadecimal characters. Downloaded and imported files always receive a checksum and content-based filename. Failed downloads or imports leave the current metadata intact. Newly copied files may remain if a later step fails; they are harmless and are not deleted automatically.

Media paths must be filenames in the same folder: no absolute paths, URLs, subfolders or traversal. JSON is limited to 256 KiB; backgrounds to 16 MiB (PNG, JPEG or WebP); video to 128 MiB (OGV or MP4); music to 32 MiB (Ogg Vorbis, MP3 or WAV). Text limits are title 256 characters, description 6000, developer/publisher/genre 160, players 48, year four digits from 1900 through 2100. `Import an offline metadata.json pack…` validates the matching game and media checksums before saving it to the collection. The current implementation does not import ES-DE `gamelist.xml` directly.

## Preview videos

Godot's built-in player supports Theora OGV. ScreenScraper supplies MP4; these previews can be opened in the default local video player. For an inline preview, convert a cached MP4 explicitly:

```sh
python3 scripts/convert-presentation-video.py /path/to/presentation/metadata.json --ffmpeg /path/to/ffmpeg
```

This requires an ffmpeg build with the `libtheora` encoder. Check the exact executable with `ffmpeg -hide_banner -encoders`: the regular Homebrew `ffmpeg` build may omit it even when another installed version supports it. Homebrew's [ffmpeg-full formula](https://formulae.brew.sh/formula/ffmpeg-full) includes Theora and is installed separately from the regular formula; an existing versioned installation can also work. Pass the executable that actually lists `libtheora` to `--ffmpeg`. The helper checks before changing any media, installs nothing, and explains when the encoder is unavailable. MP4 playback in the default player remains available.

With that encoder installed, the helper uses local ffmpeg with network protocols disabled, creates a silent Theora preview up to 120 seconds and 1280 pixels wide, verifies the unchanged source, then atomically updates the metadata. The original MP4 is retained. Reopen the game's collection to refresh. It never runs automatically when browsing games.

## Selection music

Music belongs to the selected game's presentation pack. Choose **Add local selection music…** in Game media, or import a matching `metadata.json` with a `media.music` entry and its local audio file. Enable **Game music** beside the selected game; the adjacent slider controls its volume. It starts disabled and has a separate saved volume, initially 35%, so it does not change gameplay volume. No music is invented or borrowed when the selected game has no track.

Selection music stops when entering gameplay, opening a video preview or returning to the console selection. Changing games selects the new game's track; it never layers tracks from multiple games. Keep soundtrack attribution in `media.music.source`. Downloading a background or video from ScreenScraper preserves an existing locally imported music entry.

## Verification

```sh
godot --headless --path frontend/godot-ui --script res://scripts/game_presentation_smoke.gd
godot --headless --path frontend/godot-ui --script res://scripts/selection_media_smoke.gd
python3 scripts/test-convert-presentation-video.py
```

The GDScript fixture tests cover response normalization, game identity, malformed metadata, safe paths, source URL stripping, checksum mismatch, atomic failure behavior, API account-data exclusion, cancellation and password clearing. They do not contact ScreenScraper or use personal credentials. An additional local conversion check used an original three-second test pattern and a Theora-enabled ffmpeg 7.1.5: the 512×448, 30 fps OGV was produced and the original MP4 hash remained unchanged. This does not establish authenticated provider downloads or playback of a particular game's footage. A native build is normally required by the full Godot project; these scripts can also run in an isolated project containing the presentation helpers, shared theme and preferences helper.

## Primary references and media provenance

- [ScreenScraper API v2 documentation](https://www.screenscraper.fr/webapi2.php): approval, authentication, exact-game lookup, media endpoints and quota/error responses.
- [RetroDECK's ES-DE guide](https://retrodeck.readthedocs.io/en/latest/wiki_frontend_guides/es-de/esde-guide/): explicit scraping, content choices and account setup.
- [RetroDECK's ES-DE development guide](https://retrodeck.readthedocs.io/en/latest/wiki_development/es-de/es-de-development-guide/): platform-to-ScreenScraper system IDs.
- [ES-DE user guide](https://gitlab.com/es-de/emulationstation-de/-/blob/master/USERGUIDE.md): locally cached metadata and media.

Keep downloaded game artwork and videos in the private collection. Source attribution records where media came from; it does not grant commercial rights to third-party game artwork. Neither these assets nor credentials belong in the app's public source or release package.
