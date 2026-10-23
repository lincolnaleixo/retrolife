extends RefCounted

const INK := Color("f0f4f5")
const MUTED := Color("a9bbc4")
const ACCENT := Color("a7e7ce")

static func make_theme() -> Theme:
    var result := Theme.new()
    var font := SystemFont.new()
    font.font_names = PackedStringArray(["Inter", "Helvetica Neue", "Noto Sans"])
    font.font_weight = 400
    font.allow_system_fallback = true
    result.default_font = font
    result.default_font_size = 16
    result.set_color("font_color", "Label", INK)
    for type in ["Button", "CheckButton", "CheckBox", "OptionButton", "LineEdit", "PopupMenu"]:
        result.set_font_size("font_size", type, 16)
        result.set_color("font_color", type, INK)
        result.set_color("font_hover_color", type, Color.WHITE)
        result.set_color("font_focus_color", type, Color.WHITE)
        result.set_color("font_disabled_color", type, Color("70828e"))
    for state in ["normal", "hover", "pressed", "focus", "disabled"]:
        var box := StyleBoxFlat.new()
        box.bg_color = Color("1b2933") if state == "normal" else Color("2a3b46")
        if state == "disabled": box.bg_color = Color("152029")
        if state == "focus": box.bg_color = Color.TRANSPARENT
        box.border_color = ACCENT if state == "focus" else Color("3a4d59")
        box.set_border_width_all(2 if state == "focus" else 1)
        box.set_corner_radius_all(12)
        box.content_margin_left = 16
        box.content_margin_right = 16
        box.content_margin_top = 11
        box.content_margin_bottom = 11
        for type in ["Button", "OptionButton"]:
            result.set_stylebox(state, type, box)
    for type in ["Label", "Button", "LineEdit"]:
        result.set_constant("outline_size", type, 0)
    var panel := StyleBoxFlat.new()
    panel.bg_color = Color("101c26")
    panel.border_color = Color("344955")
    panel.set_border_width_all(1)
    panel.set_corner_radius_all(18)
    panel.set_content_margin_all(22)
    result.set_stylebox("panel", "PopupPanel", panel)
    return result

static func heading_font() -> SystemFont:
    var font := SystemFont.new()
    font.font_names = PackedStringArray(["Avenir Next", "Inter", "Noto Sans"])
    font.font_weight = 700
    font.allow_system_fallback = true
    return font
