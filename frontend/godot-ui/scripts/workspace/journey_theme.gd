extends RefCounted

## Optional, inert art direction. A theme never enables achievements or changes XP.
const IDS := ["first_stage", "secret", "boss", "finale"]
const LIMIT := 16 * 1024

static func from_file(path: String) -> Dictionary:
    if path.is_empty():
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null or file.get_length() > LIMIT:
        return {}
    var source: Variant = JSON.parse_string(file.get_as_text())
    if not source is Dictionary or source.get("version") != 1:
        return {}
    var theme := {}
    for key in ["title", "subtitle", "collectionTitle"]:
        var value := _caption(source.get(key, ""), 160 if key == "subtitle" else 80)
        if not value.is_empty():
            theme[key] = value
    var raw_cards: Variant = source.get("cards", {})
    if not raw_cards is Dictionary:
        return theme
    var cards := {}
    var color_pattern := RegEx.create_from_string("^[0-9a-fA-F]{6}$")
    for id in IDS:
        var raw: Variant = raw_cards.get(id, {})
        if not raw is Dictionary:
            continue
        var card := {}
        for key in ["region", "rewardName"]:
            var value := _caption(raw.get(key, ""), 80)
            if not value.is_empty():
                card[key] = value
        var color: Variant = raw.get("accent", "")
        if color is String and color_pattern.search(color) != null:
            card["accent"] = color
        if not card.is_empty():
            cards[id] = card
    theme["cards"] = cards
    return theme

static func card(theme: Dictionary, id: String) -> Dictionary:
    return theme.get("cards", {}).get(id, {})

static func _caption(value: Variant, limit: int) -> String:
    if not value is String or value.length() > limit:
        return ""
    return value.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
