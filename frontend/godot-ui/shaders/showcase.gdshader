shader_type canvas_item;
render_mode unshaded;

void fragment() {
    // A quiet studio stage. All light is static so models remain the focal point.
    vec2 uv = UV;
    vec3 color = mix(vec3(0.028, 0.034, 0.061), vec3(0.055, 0.045, 0.085), uv.y);
    vec2 indigo_position = (uv - vec2(0.32, 0.36)) * vec2(1.05, 1.35);
    vec2 plum_position = (uv - vec2(0.75, 0.53)) * vec2(1.35, 1.25);
    float indigo_light = exp(-dot(indigo_position, indigo_position) * 7.0);
    float plum_light = exp(-dot(plum_position, plum_position) * 9.0);
    color += vec3(0.045, 0.050, 0.110) * indigo_light;
    color += vec3(0.067, 0.031, 0.077) * plum_light;

    // A broad ground glow gives the object a place in the scene without a grid.
    vec2 floor_position = (uv - vec2(0.5, 0.72)) * vec2(1.6, 9.0);
    float floor_light = exp(-dot(floor_position, floor_position) * 3.0);
    color += vec3(0.072, 0.065, 0.103) * floor_light;
    vec2 edge_position = (uv - vec2(0.5, 0.45)) * vec2(1.0, 0.8);
    float vignette = smoothstep(0.18, 0.65, length(edge_position));
    color *= 1.0 - vignette * 0.43;

    // Subpixel dithering keeps the dark gradients smooth on 8-bit displays.
    float dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))) - 0.5;
    COLOR = vec4(color + dither / 255.0, 1.0);
}
