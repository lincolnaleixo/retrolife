# Journey art packs

Journey has three presentation states:

- **Custom:** verified detector support plus the game's own external artwork.
  Illustrated chapters and collectible scenes use individual accents and names.
- **Basic:** verified support without artwork. Event names come from the backend,
  with neutral colors and numbered placeholders.
- **Absent:** no detector support. The gameplay sidebar and its toggle are hidden;
  the game is omitted from Rewards. A matching display title or art pack cannot
  enable achievements for an unsupported ROM revision.

Temporary backend errors also hide the sidebar until a valid supported summary
returns. The player's visibility preference is retained. Detection and persistence
continue while a supported Journey is hidden, and polling stops on session exit.

## Files and metadata

Assets remain in the private collection at
`reproductions/<console>/<game>/journey/`. Publish them in the media source
repository first, then mirror them to the configured local collection. Application
source and releases contain only the renderer, never these game illustrations.

The current four event IDs are `first_stage`, `secret`, `boss` and `finale`.
Chapter illustrations use `chapters/<event>.svg`; their collectible counterparts
retain `rewards/05.svg` through `08.svg`. `cover.png` is optional. Existing progress
IDs and artwork indexes do not change when replacing illustrations.

An optional `theme.json` provides inert presentation data:

```json
{
  "version": 1,
  "title": "Your field guide",
  "subtitle": "A collection of discoveries.",
  "collectionTitle": "Your treasures",
  "cards": {
    "first_stage": {
      "accent": "83df9b",
      "region": "FIRST ADVENTURE",
      "rewardName": "Island diorama"
    }
  }
}
```

Only recognized event IDs and presentation fields are read. Files are limited to
16 KiB, captions to 80 characters (160 for the subtitle), and colors to six hex
digits. Unknown versions, invalid colors and missing or oversized files fall back
without enabling content. A theme with no valid artwork cannot create a custom
presentation. Themes have no access to XP, progress mutations or executable code.

Chapter illustrations have an 88-pixel canvas; collectible art has more room in
the sidebar and Rewards hub. Use large silhouettes and readable details, with
little transparent padding. Locked illustrations retain their colors; explicit
status text distinguishes them from collected rewards. Missing files never reuse
another game's art.

`journey_art_smoke.gd`, `gameplay_window_smoke.gd` and `rewards_center_smoke.gd`
exercise custom/basic/absent states, same-title unsupported versions, bounded
metadata, stale artwork clearing, polling recovery and read-only event progress.
