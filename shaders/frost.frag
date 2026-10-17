#version 440
// Frost.qml: the blurred wallpaper under the item's rect on the screen, Hyprland's noise on it, the
// tint over that, clipped to a rounded rect with per-corner radii.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 area;      // the item on the screen, as a fraction of it: x, y, width, height
    vec2 screen;    // the screen in px
    vec2 itemSize;  // the item in px
    vec4 radii;     // top-left, top-right, bottom-right, bottom-left
    vec4 tintColor; // not premultiplied
    float noise;
    float through;  // the share of the screen Hyprland's window opacity lets through, taken back out (Frost.solid)
};
layout(binding = 1) uniform sampler2D source;

// Hyprland's blur noise: a per-pixel hash anchored to the screen, so it stays put while a surface moves
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main() {
    vec2 c = (qt_TexCoord0 - 0.5) * itemSize;
    float r = c.x < 0.0 ? (c.y < 0.0 ? radii.x : radii.w) : (c.y < 0.0 ? radii.y : radii.z);
    vec2 q = abs(c) - 0.5 * itemSize + r;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float mask = clamp(0.5 - d, 0.0, 1.0);

    vec2 uv = area.xy + qt_TexCoord0 * area.zw;
    vec3 ground = texture(source, uv).rgb + (hash(floor(uv * screen)) - 0.5) * noise;
    vec3 shown = mix(ground, tintColor.rgb, tintColor.a);
    // what lands on the screen is through * ground + (1 - through) * this: solve for `shown` there
    shown = clamp((shown - through * ground) / (1.0 - through), 0.0, 1.0);
    fragColor = vec4(shown, 1.0) * (mask * qt_Opacity);
}
