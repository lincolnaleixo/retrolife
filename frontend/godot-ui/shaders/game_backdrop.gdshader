shader_type canvas_item;
render_mode unshaded;

void fragment() {
    vec2 art_uv = vec2(clamp(UV.x - 0.15, 0.0, 1.0), UV.y);
    vec4 art = texture(TEXTURE, art_uv);
    // One continuous illustrated stage: quiet behind copy and physical media.
    float reveal = mix(0.13, 0.24, smoothstep(0.16, 0.62, UV.x));
    float edges = smoothstep(0.0, 0.18, UV.y) * (1.0 - smoothstep(0.72, 1.0, UV.y));
    vec3 ink = vec3(0.020, 0.043, 0.054);
    COLOR = vec4(mix(ink, art.rgb, reveal * (0.40 + 0.60 * edges)), 1.0);
}
