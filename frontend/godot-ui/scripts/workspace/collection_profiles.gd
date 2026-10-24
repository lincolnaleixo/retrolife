extends RefCounted

## Presentation profiles never grant emulator support. Artwork stays external.
const SYSTEMS := {
    "nes": "Nintendo Entertainment System", "snes": "Super Nintendo",
    "mega-drive": "Mega Drive", "playstation-1": "PlayStation",
    "nintendo-64": "Nintendo 64", "game-boy": "Game Boy", "game-boy-advance": "Game Boy Advance"
}
const GAMES := [
    {"match": "super mario world", "system": "snes", "slug": "super-mario-world", "title": "Super Mario World", "chapter": "A passport to Dinosaur Land", "color": "7ce4ad", "subtitle": "From Yoshi's Island to Bowser's castle. Every secret is another story.", "quests": ["Clear a stage on Yoshi's Island", "Find a red-dot level's secret exit", "Defeat a Koopaling in a castle", "Rescue Peach from Bowser"], "notes": ["Take your first steps through Dinosaur Land.", "Explore an alternate route beyond the normal goal.", "Finish a castle and open the next region.", "Complete the final battle in Bowser's castle."], "gifts": ["Dinosaur Land passport", "Yoshi's Island postcard", "Cape explorer patch", "Star Road keepsake", "Yoshi companion badge", "Secret route key", "Koopaling crest", "Peach's thank-you letter"]},
    {"match": "super mario bros", "system": "nes", "slug": "super-mario-bros", "title": "Super Mario Bros.", "chapter": "Across the Mushroom Kingdom", "color": "f3bb68", "quests": ["Reach the flag in World 1-1", "Discover a Warp Zone", "Clear a castle", "Rescue the princess in World 8-4"], "gifts": ["Mushroom passport", "Pipe traveler pin", "Fire Flower patch", "Kingdom keepsake", "First flag pennant", "Warp Zone map", "Castle crest", "Princess letter"]},
    {"match": "sonic the hedgehog", "system": "mega-drive", "slug": "sonic-the-hedgehog", "title": "Sonic the Hedgehog", "chapter": "Postcards from South Island", "color": "77cafa", "quests": ["Clear Green Hill Act 1", "Collect a Chaos Emerald", "Defeat a zone's boss", "Finish the Final Zone"], "gifts": ["South Island passport", "Green Hill postcard", "Speed trail patch", "Ring collector medal", "Green Hill pennant", "Emerald keepsake", "Robotnik crest", "Island hero trophy"]},
    {"match": "crash bandicoot", "system": "playstation-1", "slug": "crash-bandicoot", "title": "Crash Bandicoot", "chapter": "The Wumpa Island expedition", "color": "ffb477", "quests": ["Finish N. Sanity Beach", "Earn a clear gem", "Defeat Papu Papu", "Defeat Dr. Neo Cortex"], "gifts": ["Island expedition pass", "Wumpa postcard", "Jungle explorer patch", "Crate collector medal", "Beach pennant", "Gem keepsake", "Papu Papu crest", "Cortex victory trophy"]},
    {"match": "super mario 64", "system": "nintendo-64", "slug": "super-mario-64", "title": "Super Mario 64", "chapter": "Beyond the castle paintings", "color": "b8a4ff", "quests": ["Earn a star in Bob-omb Battlefield", "Find a castle secret star", "Defeat Bowser in the Dark World", "Defeat Bowser in the Sky"], "gifts": ["Castle visitor pass", "Painting postcard", "Star seeker patch", "Castle keepsake", "Battlefield star", "Secret star compass", "Bowser key crest", "Castle hero trophy"]},
    {"match": "tetris", "system": "game-boy", "slug": "tetris", "title": "Tetris", "chapter": "One more line", "color": "c6db82", "quests": ["Clear your first line", "Clear four lines with one piece", "Reach level 9 in A-Type", "Finish B-Type at level 9, height 5"], "gifts": ["Pocket puzzle pass", "Stacker postcard", "Line master patch", "Pocket champion medal", "First line tile", "Four-line crystal", "Level nine crest", "B-Type trophy"]},
    {"match": "super mario advance 4", "system": "game-boy-advance", "slug": "super-mario-advance-4", "title": "Super Mario Advance 4", "chapter": "Eight worlds in your pocket", "color": "f3cf79", "quests": ["Clear World 1-1", "Find a Warp Whistle", "Defeat Larry in Grass Land", "Rescue Peach in Dark Land"], "gifts": ["Pocket kingdom pass", "Grass Land postcard", "Raccoon explorer patch", "Eight-world keepsake", "First stage pennant", "Warp Whistle charm", "Airship crest", "Dark Land trophy"]}
]

static func for_game(title: String, system := "") -> Dictionary:
    var normalized := title.to_lower().replace(".", "").strip_edges()
    for profile in GAMES:
        var name: String = str(profile.match).replace(".", "")
        var matches := normalized == name or normalized.begins_with(name + " (") or normalized.begins_with(name + ":") or normalized.begins_with(name + " - ")
        if matches and (system.is_empty() or system == profile.system):
            return profile
    return {}

static func asset_base(profile: Dictionary) -> String:
    return "reproductions/%s/%s" % [profile.system, profile.slug] if not profile.is_empty() else ""

static func box_path(profile: Dictionary) -> String:
    if profile.is_empty():
        return ""
    return preload("res://scripts/workspace/preferences.gd").asset(asset_base(profile) + "/box/%s-%s-box.glb" % [profile.system, profile.slug])
