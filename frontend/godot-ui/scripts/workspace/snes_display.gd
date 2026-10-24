extends RefCounted

## Presentation only: the emulator frame, timing, audio and saves stay untouched.
## Geometry comes from texture dimensions and screen-space shader derivatives,
## so resizing, HiDPI and the SNES high-resolution modes need no cached sizes.

const DISPLAY_SHADER = preload("res://shaders/snes_display.gdshader")
const PRESETS: Array[Dictionary] = [
    {"id": "original", "title": "Original", "description": "Unfiltered pixels. The original picture, sharp and clear."},
    {"id": "smooth", "title": "Soft & sharp", "description": "Gentler pixel edges with a little extra definition."},
    {"id": "scanlines", "title": "Clean scanlines", "description": "Crisp pixels with fine, evenly spaced scanlines."},
    {"id": "crt", "title": "Studio CRT", "description": "A subtle tube glow, phosphor texture and curved glass."},
]


static func normalize_id(value: Variant) -> String:
    if value is String:
        for preset: Dictionary in PRESETS:
            if preset.id == value:
                return value
    return "original"


static func apply(frame: TextureRect, preset_id: String, strength: float) -> void:
    var selected := normalize_id(preset_id)
    var amount := clampf(strength, 0.0, 1.0) if is_finite(strength) else 0.0
    if selected == "original" or is_zero_approx(amount):
        frame.material = null
        frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        return

    # Each game viewport gets its own instance. Never mutate a shared material
    # or a parent Control: the journal and overlay text must remain unfiltered.
    var material := frame.material as ShaderMaterial
    if material == null or material.shader != DISPLAY_SHADER:
        material = ShaderMaterial.new()
        material.shader = DISPLAY_SHADER
        frame.material = material
    frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    material.set_shader_parameter("effect", ["smooth", "scanlines", "crt"].find(selected))
    material.set_shader_parameter("strength", amount)
