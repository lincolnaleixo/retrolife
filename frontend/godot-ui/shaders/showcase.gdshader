shader_type canvas_item;
render_mode unshaded;

void fragment() {
    vec2 p = UV - vec2(0.5, 0.39);
    float glow = exp(-dot(p * vec2(1.1, 1.8), p * vec2(1.1, 1.8)) * 5.0);
    vec3 base = mix(vec3(0.035, 0.041, 0.060), vec3(0.11, 0.115, 0.165), glow);
    vec2 dot_pos = abs(fract(FRAGCOORD.xy / 28.0) - 0.5);
    float dots = (1.0 - smoothstep(0.02, 0.043, length(dot_pos))) * 0.022;
    COLOR = vec4(base + dots * (0.25 + glow), 1.0);
}
