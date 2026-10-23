shader_type canvas_item;
render_mode unshaded;

void fragment() {
    vec4 art = texture(TEXTURE, UV);
    // The dossier protects copy; the remaining screen is an illustrated stage.
    float reveal = mix(0.10, 0.65, smoothstep(0.14, 0.55, UV.x));
    float edges = smoothstep(0.0, 0.18, UV.y) * (1.0 - smoothstep(0.76, 1.0, UV.y));
    vec3 ink = vec3(0.018, 0.028, 0.043);
    COLOR = vec4(mix(ink, art.rgb, reveal * (0.30 + 0.70 * edges)), 1.0);
}
