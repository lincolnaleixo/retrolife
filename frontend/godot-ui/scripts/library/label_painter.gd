extends Node2D

## Original neutral label artwork rendered only when a pooled slot changes.
## The top band follows the pinned model's folded label UVs.
var title := ""
var system := "SNES"
var collection_index := 0
var tone := Color("8b7db7")
var artwork: Texture2D


func configure(game: Dictionary, index: int, color: Color, local_artwork: Texture2D) -> void:
    title = str(game.get("title", "Untitled")).left(100)
    system = "SNES" if str(game.get("systemId", "")) == "snes" else str(game.get("systemId", "RETRO")).to_upper().left(12)
    collection_index = index + 1
    tone = color
    artwork = local_artwork
    queue_redraw()


func _draw() -> void:
    var bounds := Rect2(0, 0, 1024, 512)
    draw_rect(bounds, tone.darkened(0.65))
    if artwork != null:
        # Letterbox rather than stretch covers or differently shaped labels.
        var source := artwork.get_size()
        var factor := minf(1024.0 / maxf(source.x, 1.0), 512.0 / maxf(source.y, 1.0))
        var dimensions := source * factor
        draw_texture_rect(artwork, Rect2((bounds.size - dimensions) * 0.5, dimensions), false)
        return
    draw_colored_polygon(PackedVector2Array([Vector2(690, 72), Vector2(1024, 72), Vector2(1024, 512), Vector2(840, 512), Vector2(510, 200)]), tone.darkened(0.36))
    draw_colored_polygon(PackedVector2Array([Vector2(875, 72), Vector2(1024, 72), Vector2(1024, 465), Vector2(650, 72)]), tone.darkened(0.13))
    draw_rect(Rect2(0, 0, 1024, 72), tone.lightened(0.12))
    var font := ThemeDB.fallback_font
    draw_string(font, Vector2(48, 49), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 900, 34, Color("171822"))
    draw_string(font, Vector2(60, 146), "RETROLIFE  /  " + system, HORIZONTAL_ALIGNMENT_LEFT, 900, 30, Color("e0ddee"))
    var lines := _lines(title, font)
    var first_baseline := 281.0 - (lines.size() - 1) * 41.0
    for index in range(lines.size()):
        draw_string(font, Vector2(58, first_baseline + index * 86.0), lines[index], HORIZONTAL_ALIGNMENT_LEFT, 900, 76, Color("fffdf8"))
    draw_line(Vector2(60, 423), Vector2(964, 423), Color(1, 1, 1, 0.28), 2.0)
    draw_string(font, Vector2(60, 469), "COLLECTION  %03d" % collection_index, HORIZONTAL_ALIGNMENT_LEFT, 900, 26, Color("e0ddee"))


static func _lines(text: String, font: Font) -> Array[String]:
    var result: Array[String] = []
    var current := ""
    for word in text.split(" ", false):
        var candidate := current + (" " if not current.is_empty() else "") + word
        if not current.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, 76).x > 895:
            result.append(current)
            current = word
        else:
            current = candidate
    if not current.is_empty():
        result.append(current)
    if result.size() > 3:
        result.resize(3)
        result[2] = result[2].left(17) + "..."
    return result
