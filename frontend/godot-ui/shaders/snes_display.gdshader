shader_type canvas_item;
render_mode unshaded;

// Original RetroLife display effects. This pass reads only the game texture.
// No clock, noise or alternating fields: a paused frame stays completely still.
uniform int effect : hint_range(0, 2) = 0;
uniform float strength : hint_range(0.0, 1.0) = 0.7;
varying vec4 item_tint;

void vertex() {
    item_tint = COLOR;
}

vec2 pixel_center(vec2 uv, vec2 pixel) {
    vec2 center = (floor(uv / pixel) + vec2(0.5)) * pixel;
    return clamp(center, pixel * 0.5, vec2(1.0) - pixel * 0.5);
}

vec2 sample_position(vec2 uv, vec2 pixel) {
    return clamp(uv, pixel * 0.5, vec2(1.0) - pixel * 0.5);
}

void fragment() {
    vec2 pixel = TEXTURE_PIXEL_SIZE;
    vec2 uv = UV;
    float coverage = 1.0;
    if (effect == 2) {
        vec2 glass = uv * 2.0 - vec2(1.0);
        // Keep curvature restrained: only the extreme corners reach the bezel.
        glass *= 1.0 + 0.010 * strength * dot(glass, glass);
        uv = glass * 0.5 + vec2(0.5);
        vec2 edge = min(uv, vec2(1.0) - uv);
        vec2 footprint = max(fwidth(uv), vec2(0.00001));
        coverage = smoothstep(-footprint.x, footprint.x, edge.x)
            * smoothstep(-footprint.y, footprint.y, edge.y);
    }

    vec3 crisp = texture(TEXTURE, pixel_center(uv, pixel)).rgb;
    vec3 color = crisp;
    if (effect == 0) {
        vec3 center = texture(TEXTURE, sample_position(uv, pixel)).rgb;
        vec3 left = texture(TEXTURE, sample_position(uv - vec2(pixel.x, 0.0), pixel)).rgb;
        vec3 right = texture(TEXTURE, sample_position(uv + vec2(pixel.x, 0.0), pixel)).rgb;
        vec3 top = texture(TEXTURE, sample_position(uv - vec2(0.0, pixel.y), pixel)).rgb;
        vec3 bottom = texture(TEXTURE, sample_position(uv + vec2(0.0, pixel.y), pixel)).rgb;
        vec3 neighbors = (left + right + top + bottom) * 0.25;
        vec3 low = min(center, min(min(left, right), min(top, bottom)));
        vec3 high = max(center, max(max(left, right), max(top, bottom)));
        // A bounded unsharp pass avoids light rings around dark sprite outlines.
        vec3 defined = clamp(center + (center - neighbors) * 0.18, low, high);
        color = mix(crisp, defined, strength);
    } else {
        if (effect == 2) {
            vec3 center = texture(TEXTURE, sample_position(uv, pixel)).rgb;
            // Horizontal beam diffusion respects wide SNES pixels instead of
            // stretching a square-pixel kernel across the final 4:3 picture.
            vec3 beam = texture(TEXTURE, sample_position(uv - vec2(pixel.x * 0.65, 0.0), pixel)).rgb
                + texture(TEXTURE, sample_position(uv + vec2(pixel.x * 0.65, 0.0), pixel)).rgb;
            color = mix(crisp, center, 0.55 * strength);
            color += max(beam * 0.5 - color, vec3(0.0)) * (0.055 * strength);
        }

        // Double-height output contains the two interlaced fields. Show a stable
        // 224/239-line beam pattern without inventing temporal field flicker.
        float source_rows = 1.0 / pixel.y;
        float beam_rows = source_rows > 300.0 ? source_rows * 0.5 : source_rows;
        float line_footprint = max(fwidth(uv.y) * beam_rows, 0.00001);
        float pixels_per_line = 1.0 / line_footprint;
        float resolvable = smoothstep(2.0, 3.5, pixels_per_line);
        // Integrating the cosine over the destination pixel keeps non-integer
        // scales stable. Fade out detail when the viewport cannot resolve it.
        float phase_width = min(line_footprint * PI, PI);
        float integration = sin(phase_width) / max(phase_width, 0.00001);
        float dark_line = 0.5 + 0.5 * cos(uv.y * beam_rows * TAU) * integration;
        float depth = (effect == 2 ? 0.22 : 0.24) * strength * resolvable;
        color *= (1.0 - depth * dark_line) * (1.0 + depth * 0.38);

        if (effect == 2) {
            // A screen-aligned six-pixel RGB triad, not a source-image pattern.
            // Its channel average is neutral; it never creates a moving rainbow.
            float column = mod(floor(FRAGCOORD.x / 2.0), 3.0);
            vec3 phosphor = vec3(0.96);
            if (column < 1.0) {
                phosphor.r = 1.08;
            } else if (column < 2.0) {
                phosphor.g = 1.08;
            } else {
                phosphor.b = 1.08;
            }
            color *= mix(vec3(1.0), phosphor, strength * resolvable * 0.65);
            vec2 edge_distance = abs(UV * 2.0 - vec2(1.0));
            float corners = pow(edge_distance.x * edge_distance.y, 2.0);
            color *= 1.0 - 0.10 * strength * corners;
        }
    }
    COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), coverage) * item_tint;
}
