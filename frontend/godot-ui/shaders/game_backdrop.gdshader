shader_type canvas_item;
render_mode unshaded;

void fragment() {
    vec4 art = texture(TEXTURE, UV);
    // Keep the selected game's scenery visible while reserving contrast for copy.
    float left_shade = mix(0.07, 0.32, smoothstep(0.12, 0.68, UV.x));
    float edge_shade = smoothstep(0.0, 0.22, UV.y) * (1.0 - smoothstep(0.63, 1.0, UV.y));
    vec3 ink = vec3(0.028, 0.050, 0.061);
    COLOR = vec4(mix(ink, art.rgb, left_shade * (0.48 + 0.52 * edge_shade)), 1.0);
}
