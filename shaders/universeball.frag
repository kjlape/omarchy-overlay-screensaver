#version 440

// Port of "Universe Ball 2" (https://www.shadertoy.com/view/WcGcWV) by
// Matt Vianueva, 2025 — License: MIT (relicensed by permission, 8-Mar-2026),
// attribution preserved. Upstream xscreensaver ships this as
// hacks/glx/glsl/universeball.glsl.
// Adapted for Qt 6 ShaderEffect: mainImage(out vec4, fragCoord) became
// qt_TexCoord0 in [0,1]; iTime became the `time` uniform (seconds);
// iResolution became the `aspect` uniform (surface w/h). First port done
// under the multi-shader API — stages resolve dynamically from the shader
// name via Service.qml `knownShaders`.
//
// Coordinate-conversion gotcha (bit us here — keep for future ports):
// shadertoy computes u = (2*fragCoord - res.xy) / res.y with
// fragCoord = uv * (aspect, 1), which simplifies to u = (2*uv - 1) * vec2(aspect, 1).
// Naively writing (2*uv - vec2(aspect, 1)) is WRONG: it yields x in
// [-aspect, 2-aspect] — skewed and mis-scaled (the "off center, stretched
// on x" look) — instead of [-aspect, aspect]. Qt's qt_TexCoord0 also runs
// top-down where shadertoy runs bottom-up, so y flips: 1 - 2*uv.y.

#define PALETTE vec3(6,4,2)

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
    float n, i, s, t = time * 0.2, d, v;
    vec3 q, p, c;
    vec2 u = (qt_TexCoord0 * 2.0 - 1.0) * vec2(aspect, 1.0);
    u.y = -u.y; // Qt texcoords run top-down; shadertoy runs bottom-up
    vec2 l = u - (u.yx * 0.9 + 0.3 - vec2(-0.35, 0.15));

    c = vec3(0.0); // jwz: shadertoy leaves o undefined until the loop
    d = 0.0;
    i = 0.0;

    for (; i++ < 5e1 && d < 5e1;
         d += s = min(q.y = 0.01 + 0.6 * abs(24.0 - length(q.xy)),
                      v = max(s, dot(abs(fract(p) - 0.5), vec3(0.04)))),
         c += (1.0 + cos(p.z + PALETTE)) / v
            + d * vec3(5, 2, 1) / q.y / 1e1
            + 7.0 * vec3(3, 4, 1) / length(l)
        )
        for (q = p = vec3(u * d, d - 16.0),
             s = length(p) - 8.0,
             p.xy *= mat2(cos(t + p.z * 0.6 + vec4(0, 33, 11, 0))),
             p += cos(t + p.zxy) + cos(t + p.yzx * s) / s / 4.0,
             p += 0.5 * cos(t + dot(cos(t + p), p) * p),
             n = 0.02; n < 2.0; n *= 1.6
        )
            q.y -= abs(dot(sin(4.0 * t + 0.3 * q / n), q - q + n));

    c = mix(c, c.yzx, smoothstep(2.0, 0.1, length(u) * 1.0));
    fragColor.rgb = tanh(c * c / 6e7 / length(u - 0.3) + 0.1 * length(u));
    fragColor.a = 1.0;
}
