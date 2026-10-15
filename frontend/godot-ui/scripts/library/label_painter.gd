extends Node2D

## Original neutral label artwork rendered only when a pooled slot changes.
## The top band follows the pinned model's folded label UVs.
var title := ""
var system := "SNES"
var collection_index := 0
var tone := Color("8b7db7")
var artwork: Texture2D
var canvas_size := Vector2(1024, 512)
var label_ratio := 2.0
var top_fold_ratio := 0.0
var disc := false


func configure(game: Dictionary, index: int, color: Color, local_artwork: Texture2D, profile: Dictionary = {}) -> void:
    title = str(game.get("title", "Untitled")).left(100)
    system = str(profile.get("name", game.get("systemId", "RETRO"))).to_upper().left(12)
    canvas_size = Vector2(profile.get("canvas", Vector2i(1024, 512)))
    label_ratio = float(profile.get("front_ratio", 2.0))
    top_fold_ratio = float(profile.get("top_fold_ratio", 0.0))
    disc = bool(profile.get("disc", false))
    collection_index = index + 1
    tone = color
    artwork = local_artwork
    queue_redraw()


func _draw() -> void:
    var bounds := Rect2(Vector2.ZERO, canvas_size)
    draw_rect(bounds, tone.darkened(0.65))
    if artwork != null:
        var source := artwork.get_size()
        var ratio := source.x / maxf(source.y, 1.0)
        if absf(ratio - label_ratio) <= label_ratio * 0.08:
            # Collection labels share this surface's UV layout: draw them to
            # fill so front and folded-top regions stay aligned.
            draw_texture_rect(artwork, bounds, false)
            return
        # Letterbox rather than stretch covers or differently shaped labels.
        var factor := minf(canvas_size.x / maxf(source.x, 1.0), canvas_size.y / maxf(source.y, 1.0))
        var dimensions := source * factor
        draw_texture_rect(artwork, Rect2((bounds.size - dimensions) * 0.5, dimensions), false)
        return
    if disc:
        _draw_disc()
        return
    if canvas_size.y != 512.0:
        _draw_cover()
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


func _draw_cover() -> void:
    # Keep lettering upright and undistorted on square media artwork and
    # the taller cartridge labels. Artwork is letterboxed above using this
    # same physical aspect ratio.
    var height := canvas_size.y
    var band := height * top_fold_ratio if top_fold_ratio > 0.0 else 72.0
    draw_colored_polygon(PackedVector2Array([Vector2(530, band), Vector2(1024, band), Vector2(1024, height), Vector2(770, height), Vector2(420, height * 0.42)]), tone.darkened(0.36))
    draw_colored_polygon(PackedVector2Array([Vector2(875, band), Vector2(1024, band), Vector2(1024, height * 0.91), Vector2(650, band)]), tone.darkened(0.13))
    draw_rect(Rect2(0, 0, 1024, band), tone.lightened(0.12))
    var font := ThemeDB.fallback_font
    var band_title := title.to_upper() if top_fold_ratio > 0.0 else system
    draw_string(font, Vector2(48, band * 0.5 + 12), band_title, HORIZONTAL_ALIGNMENT_LEFT, 900, 34, Color("171822"))
    draw_string(font, Vector2(60, maxf(146.0, band + 60.0)), "RETROLIFE  /  COLLECTION", HORIZONTAL_ALIGNMENT_LEFT, 900, 30, Color("e0ddee"))
    var lines := _lines(title, font)
    var first_baseline := height * 0.55 - (lines.size() - 1) * 41.0
    for index in range(lines.size()):
        draw_string(font, Vector2(58, first_baseline + index * 86.0), lines[index], HORIZONTAL_ALIGNMENT_LEFT, 900, 76, Color("fffdf8"))
    draw_line(Vector2(60, height - 89), Vector2(964, height - 89), Color(1, 1, 1, 0.28), 2.0)
    draw_string(font, Vector2(60, height - 43), "COLLECTION  %03d" % collection_index, HORIZONTAL_ALIGNMENT_LEFT, 900, 26, Color("e0ddee"))


func _draw_disc() -> void:
    # Place the title above the physical hub; a centered cover title would be
    # cut in half by the annular mesh's intentionally empty center.
    draw_arc(Vector2(512, 512), 455, 0, TAU, 128, tone.lightened(0.15), 16, true)
    var font := ThemeDB.fallback_font
    var lines := _lines(title, font)
    for index in range(mini(lines.size(), 2)):
        draw_string(font, Vector2(190, 278 + 58 * index), lines[index], HORIZONTAL_ALIGNMENT_CENTER, 644, 46, Color("fffdf8"))
    draw_string(font, Vector2(222, 786), system, HORIZONTAL_ALIGNMENT_CENTER, 580, 34, Color("e0ddee"))
    draw_string(font, Vector2(222, 838), "COLLECTION  %03d" % collection_index, HORIZONTAL_ALIGNMENT_CENTER, 580, 24, Color("e0ddee"))


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
