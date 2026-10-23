extends Control

var accent := Color("7ce4ad")
var earned := false
var symbol := 0
var artwork: Texture2D

func _ready() -> void:
    custom_minimum_size = custom_minimum_size.max(Vector2(38, 38))
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
    var ink := accent if earned else Color("6b7b8c")
    if artwork != null:
        var available := size - Vector2(8, 8)
        var dimensions := Vector2(artwork.get_width(), artwork.get_height())
        var ratio := minf(available.x / dimensions.x, available.y / dimensions.y)
        var target := dimensions * ratio
        # Art remains a colorful preview; the containing card names the lock state.
        draw_texture_rect(artwork, Rect2((size - target) * 0.5, target), false, Color.WHITE)
        return
    # A missing game-specific illustration stays typographic and neutral.
    var font := get_theme_default_font()
    var caption := "%02d" % [symbol + 1]
    var extent := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
    draw_string(font, Vector2((size.x - extent.x) * 0.5, (size.y + font.get_ascent(20)) * 0.5 - 3), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
