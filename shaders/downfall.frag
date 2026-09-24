#version 440

// Port of "Downfall" (https://www.shadertoy.com/view/w3sBWl) by
// Matt Vianueva, 2025 — License: MIT (relicensed by permission, 8-Mar-2026),
// attribution preserved. Upstream xscreensaver ships this as
// hacks/glx/glsl/downfall.glsl.
// Adapted for Qt 6 ShaderEffect: mainImage(out vec4, fragCoord) became
// qt_TexCoord0 in [0,1]; iTime became the `time` uniform (seconds);
// iResolution became the `aspect` uniform (surface w/h). No iMouse — the
// animation is time-driven upstream already.
//
// Coordinate-conversion gotcha (bit universeball — keep for future ports):
// shadertoy computes u = (2*fragCoord - res.xy) / res.y with
// fragCoord = uv * (aspect, 1), which simplifies to u = (2*uv - 1) * vec2(aspect, 1).
// Naively writing (2*uv - vec2(aspect, 1)) is WRONG: it yields x in
// [-aspect, 2-aspect] — skewed and mis-scaled (the "off center, stretched
// on x" look) — instead of [-aspect, aspect]. Qt's qt_TexCoord0 also runs
// top-down where shadertoy runs bottom-up, so y flips: 1 - 2*uv.y.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;   // seconds since shader show
    float aspect; // surface width / height
};

void main()
{
    vec4 o = vec4(0.0); // jwz: shadertoy leaves o undefined until written
    float i = 0.0, d = 0.0, s = 0.0;
    float t = time;
    vec3 p = vec3(0.0);
    vec2 u = (qt_TexCoord0 * 2.0 - 1.0) * vec2(aspect, 1.0);
    u.y = -u.y; // Qt texcoords run top-down; shadertoy runs bottom-up
    mat2 r = mat2(cos(1.2 + vec4(0, 33, 11, 0)));

    for (; i++ < 1e2;) {
        p = vec3(u * d, d - 24.0);
        p.yz *= r;
        p.z += t * 3e1;

        for (s = 0.03; s < 4.0; s += s)
            p.yz -= abs(dot(sin(t + t + 0.32 * p / s), vec3(s)));

        p *= vec3(0.2, 0.6, 1.0);
        d += s = 0.3 + 0.3 * abs(2.0 - length(p.xy));
        o += 1.0 / s;
    }

    o = tanh(o * o / 1e4);
    fragColor = o;
    fragColor.a = 1.0;
}
