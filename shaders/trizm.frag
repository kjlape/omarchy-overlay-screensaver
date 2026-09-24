#version 440

// Title:  Trizm
// Author: Matt Vianueva <diatribes@gmail.com>
// URL:    https://www.shadertoy.com/view/3fcBD8
// Date:   14-Dec-2025
// Desc:   Trizm

// Relicensed as MIT License, by permission, 8-Mar-2026.

/*
    I thought @OldEclipse's "Cyber Conduits"
    was so cool I had to play with triangle
    waves more.

    @OldEclipse - "Cyber Conduits"
        https://www.shadertoy.com/view/tf3fR7

    Can also use them to create cool surfaces:
        https://www.shadertoy.com/view/tXX3RX

    Which was learned from @Shane's "Abstract Corridor":
        https://www.shadertoy.com/view/MlXSWX

    See also forked shader here for similar thing to this shader:
        https://www.shadertoy.com/view/3ftBWr

*/

// Port of upstream xscreensaver hacks/glx/glsl/trizm.glsl (6.16 tree,
// vendored in-repo). Adapted for Qt 6 ShaderEffect:
// - mainImage(out vec4, fragCoord) became qt_TexCoord0 in [0,1]. Upstream
//   maps uv = (u+u-r.xy)/r.y (the res.y-normalized family, roadmap tip 9):
//   with fragCoord = uv·(aspect,1) that simplifies to
//   u = (2*qt_TexCoord0 - 1) * vec2(aspect, 1) — NOT a vec2(aspect,1)
//   translation (the universeball skew bug, tip 1) — plus a y flip because
//   Qt texcoords run top-down and shadertoy bottom-up. Upstream converts
//   inside the loop from raw pixel fragCoord; here u is converted once
//   up front, so the loop's p line reduces to u * d.
// - iTime became the `time` uniform (seconds); iResolution became the
//   `aspect` uniform (surface w/h), rebuilt locally as
//   r = vec3(aspect, 1, 1) since only r.xy and r.y are used. No iMouse /
//   texture dependencies.
// - Upstream seeds d with 0.05*fract(sin(fragCoord)) on raw pixel coords
//   (a start-distance anti-banding dither). Pixel coords aren't available
//   through the aspect-only uniform, so the dither runs on the converted
//   u instead — same role, near-zero jitter only at the exact center.
// - Upstream's pre-loop `o *= i` (i = 0) is a no-op that exists only
//   because shadertoy requires the output be written before the loop
//   reads it; dropped, with `o` initialized at declaration (jwz init
//   convention) so the in-loop accumulation starts from a defined value.

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
    float i = 0.0;      // raymarch iterator
    float s = 0.0;      // sample distance
    float t = time * 0.5;

    // Coordinate conversion: shadertoy's u = (2*fragCoord - res)/res.y with
    // fragCoord = uv*(aspect,1) simplifies to u = (2*qt_TexCoord0 - 1)*vec2(aspect,1);
    // then flip y (Qt texcoords run top-down, shadertoy bottom-up).
    vec2 u = (qt_TexCoord0 * 2.0 - 1.0) * vec2(aspect, 1.0);
    u.y = -u.y; // Qt texcoords run top-down; shadertoy runs bottom-up

    vec3 r = vec3(aspect, 1.0, 1.0); // jwz: was iResolution; only .xy and .y are used

    // total distance, modulate starting point (see header re: the dither)
    float d = 0.05 * dot(fract(sin(u)), sin(u))
            + (9.0 + 2.0 * sin(t));

    vec3 p = vec3(0.0);

    // 20 iterations
    for (; i++ < 2e1; ) {
        // get position
        p = vec3(u * d, d);

        // spin by time, twist by dist
        p.xy *= mat2(cos(0.1 * p.z + 0.1 * t + vec4(0, 33, 11, 0)));

        // triangle wave distortion loop
        // arcsin(sin(x)) makes a triangle wave
        for (s = 0.0; s++ < 3.0;)
            p.xy -= asin(sin(0.6 * t + p.yx * s)) / s;

        // accumulate distance to a triangle wave
        // based on p, which has been distorted by tri waves above,
        // this triangle wave is done using fract
        d += s = dot(abs(fract(p) - 0.5), vec3(0.08));

        // accumulate color
        o += 14.0 / s
           + (1e1 * (1.0 + cos(p.y * 0.1 + p.z + vec4(3, 1, 0, 0))) / s)
           // plasma'ish lights
           * abs(1.0 / dot(cos(t + t + p * 0.35), vec3(1)));
    }

    // tanh tonemap, brightness
    o = tanh(o / 3e4);

    fragColor = o;
    fragColor.a = 1.0;
}
