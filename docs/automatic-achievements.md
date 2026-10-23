# Automatic achievement detection

Achievements are local, read-only observations of emulated game events. They do not
modify the game, require a checkbox, or unlock because the title screen has been
running. The first detector supports the unmodified **Super Mario World (USA)**
ROM only. Other games and revisions need their own verified detector.

## Content identity and memory access

The USA ROM is identified by SHA-256
`0838e531fe22c077528febe14cb3ff7c492f1f5fa8de354192bdff7137c27f5b`.
Its MD5 is `cdd3c8c37322978ca8669b34bc89c804`, also listed by
[RetroAchievements for its supported USA revision](https://retroachievements.org/game/228/hashes).
The filename and displayed game title never enable detection.

The pinned [bsnes-jg libretro implementation](https://github.com/libretro/bsnes-jg/blob/aa11568fff267fca3424cbdfa6da788ddc42e468/libretro/libretro.cpp#L973)
exposes `RETRO_MEMORY_SYSTEM_RAM`. Its
[MainRAM implementation](https://github.com/libretro/bsnes-jg/blob/aa11568fff267fca3424cbdfa6da788ddc42e468/src/bsnes.cpp#L106)
returns 128 KiB of SNES WRAM. A SNES address `$7E:xxxx` therefore corresponds to
offset `0xxxxx` in this memory, not a CPU-bus address passed to the core.

The observer reads memory only after an emulated frame, on the core's thread.
The UI receives observations and never receives a writable memory pointer.

## Observed fields

The [SMWDisX RAM declarations](https://github.com/IsoFrieze/SMWDisX/blob/30643c7595a7d097d731de69476f8059c7cf98c3/rammap.asm)
and [USA symbol addresses](https://github.com/IsoFrieze/SMWDisX/blob/30643c7595a7d097d731de69476f8059c7cf98c3/SMW_U.sym)
identify these fields:

| WRAM offset | Meaning |
| --- | --- |
| `0x0100` | Game mode; `0x14` is a running level. Title/demo and save-selection modes are different. |
| `0x0109` | Overworld override; excludes the introductory scripted level. |
| `0x010A` | Selected save file, 0–2. |
| `0x0DB3` | Active player, Mario or Luigi. |
| `0x0DD5` | Level exit outcome, interpreted only at a witnessed transition. |
| `0x13BF` | Overworld level identifier, retained across sublevels. |
| `0x13D4` | In-game pause flag. |
| `0x0071` | Player animation; 9 is death, `0x0B` freezes player input. |
| `0x1426` | Message-box trigger. |
| `0x190D` | Bowser's final rescue scene flag. |

## Event rules

The [level-ending routines in bank 00](https://github.com/IsoFrieze/SMWDisX/blob/30643c7595a7d097d731de69476f8059c7cf98c3/bank_00.asm)
write `0x0DD5` as 1 for a normal exit or 2 for a secret exit. `CODE_00C9FE`
changes game mode in that same frame. Valid destination modes are `0x0B`,
`0x0C`, `0x10` (the 100-star bonus game), and `0x18` (castle cutscene).
Death and Start+Select use `0x80`; leaving through a side exit uses zero.
These are not completions.

The [overworld routines in bank 04](https://github.com/IsoFrieze/SMWDisX/blob/30643c7595a7d097d731de69476f8059c7cf98c3/bank_04.asm)
clear the exit outcome during normal overworld handling and player transitions,
including `OWPU_NotAutoWalk`, `CODE_04937A`, and `CODE_049DAF`.
Loading a save also clears it. Detection requires a fresh **0 → 1/2** transition
immediately following an observed, unpaused live level, with the same save file,
player and level identifier. Existing save flags and exit totals are not awards.

The [SMW level definitions in Archipelago](https://github.com/ArchipelagoMW/Archipelago/blob/5e7aa38424317d1492a81118935831b567d7e5ac/worlds/smw/Levels.py)
cross-check the original level identifiers:

| Achievement | Required event |
| --- | --- |
| `first_stage` | Normal completion of one of Yoshi's Island's four stages: `0x29`, `0x2A`, `0x27`, `0x26`. |
| `secret` | A witnessed secret exit (outcome 2). |
| `boss` | Completion of a Koopaling castle: `0x25`, `0x07`, `0x40`, `0x0E`, `0x20`, `0x1A`, `0x34`. |
| `finale` | Bowser rescue event from front door `0x31` or back door `0x32`. |

For the rescue, [bank 03's `CODE_03AC03`](https://github.com/IsoFrieze/SMWDisX/blob/30643c7595a7d097d731de69476f8059c7cf98c3/bank_03.asm)
sets player animation to `0x0B` and increments `FinalCutscene` after Bowser's final
defeat. The detector requires the flag's **0 → 1** edge while still in game mode
`0x14`, following the same witnessed Bowser level. Simply loading an ending or
seeing a credits game mode does not unlock it.

## Discontinuities and verification limits

Missing/truncated memory, launch, reset and stop discard transitional evidence.
Reset preserves awards already observed in that session. Starting another game
clears the detector's session results. The persistence layer independently keeps
verified awards, so replaying an event cannot grant duplicate XP.

Frame counting excludes menus, demos, the scripted intro, in-game pause, death,
message boxes and input-frozen scenes. Play time is a statistic, not an
achievement condition. Any future save-state loading or rewind implementation
must explicitly reset detector evidence at its discontinuity.

Unit tests cover source-derived normal/secret/castle/bonus-game/Bowser sequences,
repeat observations, title/demo/pause, death/side exit/Start+Select, existing saves,
stale outcomes, changed player/save/level, missing memory and reset. These fixtures
test the detector rules; they do not replace a full-game end-to-end playthrough.

## Existing journals

Version-one journals stored manual checks and elapsed emulator time. On the first
successful save, the original bytes are archived as `journey.v1-backup.json` beside
`journey.json`. Every old record also remains in the version-two `legacy` field.
These records do not count as verified XP, levels or collected achievements.
The four event rewards each grant 100 XP once; 200 XP advances a level.

The observer continues running while Journey is hidden. New awards are saved on
ordinary emulator polling; active play time is checkpointed every 30 seconds and
on stop. A journal write failure keeps the session's save barrier active and can
be retried before a clean exit. ROMs, battery saves and game memory are unchanged.
