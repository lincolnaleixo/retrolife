extends RefCounted

## Original RetroLife interface pictograms. No external marks or game artwork.
const SHAPES := {
    "save": '<path d="M4 3h13l4 4v14H3V3zM7 3v6h10V3M7 21v-8h10v8M14 5v2"/>',
    "restore": '<path d="M4 9a8 8 0 1 1 0 6M4 3v6h6M12 7v5l3 2"/>',
    "trophy": '<path d="M8 3h8v7a4 4 0 0 1-8 0zM8 5H4v3a4 4 0 0 0 4 4m8-7h4v3a4 4 0 0 1-4 4M12 14v4m-4 3h8m-6-3h4v3"/>',
    "book": '<path d="M12 5C9 3 5 3 2 4v15c3-1 7-1 10 1 3-2 7-2 10-1V4c-3-1-7-1-10 1zM12 5v15M5 8h4m-4 4h4m6-4h4m-4 4h4"/>',
    "sidebar": '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M15 4v16m3-11v6"/>',
    "pause": '<rect x="6" y="4" width="3" height="16" rx="1"/><rect x="15" y="4" width="3" height="16" rx="1"/>',
    "play": '<path d="M8 4l12 8-12 8z"/>',
    "box": '<path d="M3 7l9-4 9 4v11l-9 4-9-4zM3 7l9 4 9-4M12 11v11M7 5l9 4"/>',
    "search": '<circle cx="10" cy="10" r="6.5"/><path d="M15 15l6 6"/>',
    "back": '<path d="M14 5l-7 7 7 7M7 12h14"/>',
    "menu": '<path d="M4 6h16M4 12h12M4 18h16"/>',
    "settings": '<path d="M4 6h16M4 12h16M4 18h16"/><rect x="8" y="3" width="4" height="6" rx="1"/><rect x="15" y="9" width="4" height="6" rx="1"/><rect x="6" y="15" width="4" height="6" rx="1"/>',
    "monitor": '<rect x="3" y="3" width="18" height="13" rx="3"/><path d="M12 16v5m-5 0h10"/>',
    "controller": '<path d="M8 6h8q4 0 5 6l1 5q0 4-4 2l-3-3H9l-3 3q-4 2-4-2l1-5q1-6 5-6zM7 9v5m-2-2.5h4m7-2h.01m3 3h.01"/>',
    "download": '<path d="M12 3v12m-5-5l5 5 5-5M4 16v5h16v-5"/>',
    "close": '<path d="M6 6l12 12M18 6L6 18"/>',
    "spark": '<path d="M12 2l3 7 7 3-7 3-3 7-3-7-7-3 7-3z"/>',
}
static var _cache: Dictionary = {}

static func icon(name: String, color := Color("c7d9df"), pixels := 22) -> Texture2D:
    var key := name + color.to_html() + str(pixels)
    if _cache.has(key):
        return _cache[key]
    var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 24 24"><g fill="none" stroke="#%s" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % [pixels, pixels, color.to_html(false), SHAPES.get(name, SHAPES.spark)]
    var image := Image.new()
    if image.load_svg_from_string(svg) != OK:
        return null
    var texture := ImageTexture.create_from_image(image)
    _cache[key] = texture
    return texture
