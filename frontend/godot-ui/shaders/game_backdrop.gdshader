shader_type canvas_item;
render_mode unshaded;

void fragment() {
    // Carry each game's palette into the stage without repeating the box's
    // characters behind the physical collectibles. Mipmaps are generated on load.
    vec3 art = textureLod(TEXTURE, UV, 7.0).rgb;
    float reveal = mix(0.10, 0.28, smoothstep(0.16, 0.62, UV.x));
    float edges = smoothstep(0.0, 0.18, UV.y) * (1.0 - smoothstep(0.72, 1.0, UV.y));
    vec3 ink = vec3(0.020, 0.043, 0.054);
    COLOR = vec4(mix(ink, art, reveal * (0.40 + 0.60 * edges)), 1.0);
}
