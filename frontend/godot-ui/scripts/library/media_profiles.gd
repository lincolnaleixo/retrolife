extends RefCounted

## Presentation metadata only. These IDs never grant import or core support.
const PROFILES := {
    "snes": {"path": "res://assets/cartridges/snes-ntsc-u.glb", "name": "SNES", "canvas": Vector2i(1024, 512), "front_ratio": 2.0, "rear_ratio": 2.0},
    "mega-drive": {"path": "res://assets/cartridges/mega-drive/mega-drive.glb", "name": "MEGA DRIVE", "canvas": Vector2i(1024, 927), "front_ratio": 74.0 / 67.0, "rear_ratio": 77.75 / 21.75, "top_fold_ratio": 7.0 / 67.0},
    "playstation-1": {"path": "res://assets/cartridges/playstation-1/playstation-1.glb", "name": "PLAYSTATION", "canvas": Vector2i(1024, 1024), "front_ratio": 1.0, "rear_ratio": 1.0, "disc": true},
    "generic": {"path": "", "name": "RETRO", "canvas": Vector2i(1024, 512), "front_ratio": 2.0, "rear_ratio": 2.0},
}


static func id_for(game: Dictionary) -> String:
    # systemId is the existing bridge DTO. Accept common import/preview aliases
    # here without extending the backend's supported systems or filters.
    var system := str(game.get("systemId", "")).strip_edges().to_lower().replace("_", "-")
    match system:
        "snes", "snes-ntsc-u", "super-nintendo":
            return "snes"
        "mega-drive", "megadrive", "genesis", "sega-genesis", "md":
            return "mega-drive"
        "playstation-1", "playstation", "ps1", "psx":
            return "playstation-1"
    return "generic"


static func for_game(game: Dictionary) -> Dictionary:
    return PROFILES[id_for(game)]


static func collection_title(game: Dictionary) -> String:
    # The currently approved label index contains SNES artwork only. A same-
    # named title on another platform must not receive or fetch its SNES label.
    return str(game.get("title", "")) if id_for(game) == "snes" else ""
