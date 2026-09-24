#version 440

// Port of "Hexagon Plasma" (https://www.shadertoy.com/view/3fy3z3) by
// Nemerix, 2025-05-26 — License: MIT ("Code made available under the MIT
// license"), attribution preserved. Upstream xscreensaver ships this as
// hacks/glx/glsl/hexplasma.glsl.
// Adapted for Qt 6 ShaderEffect: mainImage(out vec4, fragCoord) became
// qt_TexCoord0 in [0,1]; iTime became the `time` uniform (seconds);
// iResolution became the `aspect` uniform (surface w/h). No iMouse or
// texture channels to drop — the only conversion is coordinates and the
// uniform block.
//
// Coordinate conversion (universeball gotcha, keep for future ports):
// shadertoy computes u = (2*fragCoord - res.xy) / res.y with
// fragCoord = uv * (aspect, 1), which simplifies to u = (2*uv - 1) * vec2(aspect, 1).
// Do NOT write (2*uv - vec2(aspect, 1)) — that skews and stretches x.
// Qt's qt_TexCoord0 runs top-down where shadertoy runs bottom-up, so flip y.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;   // seconds since shader show
    float aspect; // surface width / height
};

float sqr(float x) { return x*x; }

float hexSdf(in vec2 pos)
{
    return max(max(abs(dot(pos, vec2(0,2))), abs(dot(pos, vec2(1.732,1)))), abs(dot(pos, vec2(1.732,-1))));
}

float smoothSdf(in vec2 pos)
{
    return mix(sqr(hexSdf(pos)), dot(pos, pos), smoothstep(0.8, 1.5, dot(pos, pos)));
}

float sfield(in vec2 s)
{
    return s.x * s.y;
}

vec3 cmap(in vec2 pos)
{
    return mix(vec3(0.1,0.6,0.8), vec3(0.5), 0.7 * tanh(dot(pos, pos)));
}

const mat2 R = mat2(0.6, 0.8, -0.8, 0.6);

void main()
{
    vec2 u = (qt_TexCoord0 * 2.0 - 1.0) * vec2(aspect, 1.0);
    u.y = -u.y; // Qt texcoords run top-down; shadertoy runs bottom-up

    float d = smoothSdf(u) - 1.0;
    d = sqrt(abs(d));

    vec2 samp = u * d;
    float y = 0.0;
    float scale = 1.0;

    for (int i = 0; i < 4; ++i)
    {
        samp = sin(R * samp * hexSdf(samp) + vec2(time)); // jwz: was vec2(iTime)
        y += scale * sfield(samp);
        scale *= 0.75;
    }

    vec3 col = cmap(u) / abs(y);
    col = tanh(0.1 * col);
    fragColor = vec4(col, 1);
}
