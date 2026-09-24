#version 440

// Port of "Star Nest" (https://www.shadertoy.com/view/XlfGRj) by Pablo
// Roman Andrioli (Kali), 2013 — License: MIT, attribution preserved.
// Upstream xscreensaver ships this as hacks/glx/glsl/starnest.glsl.
// Adapted for Qt 6 ShaderEffect: mainImage(fragCoord, iResolution) became
// uv in [0,1] from the default vertex stage; iTime/iMouse became the
// `time` (seconds) and `aspect` uniforms driven from QML. Mouse steering
// is dropped (a screensaver shouldn't depend on pointer position).

#define iterations 17
#define formuparam 0.53

#define volsteps 20
#define stepsize 0.1

#define zoom   0.800
#define tile   0.850
#define speed  0.010

#define brightness 0.0015
#define darkmatter 0.300
#define distfading 0.730
#define saturation 0.850

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
    // get coords and direction
    vec2 p = qt_TexCoord0 - 0.5;
    p.y *= aspect;
    vec3 dir = vec3(p * zoom, 1.0);
    float t = time * speed + 0.25;

    // fixed rotation (mouse steering removed for screensaver use)
    float a1 = 0.5;
    float a2 = 0.8;
    mat2 rot1 = mat2(cos(a1), sin(a1), -sin(a1), cos(a1));
    mat2 rot2 = mat2(cos(a2), sin(a2), -sin(a2), cos(a2));
    dir.xz *= rot1;
    dir.xy *= rot2;
    vec3 from = vec3(1.0, 0.5, 0.5);
    from += vec3(t * 2.0, t, -2.0);
    from.xz *= rot1;
    from.xy *= rot2;

    // volumetric rendering
    float s = 0.1, fade = 1.0;
    vec3 v = vec3(0.0);
    for (int r = 0; r < volsteps; r++) {
        vec3 q = from + s * dir * 0.5;
        q = abs(vec3(tile) - mod(q, vec3(tile * 2.0))); // tiling fold
        float pa, a = pa = 0.0;
        for (int i = 0; i < iterations; i++) {
            q = abs(q) / dot(q, q) - formuparam; // the magic formula
            a += abs(length(q) - pa);             // absolute sum of average change
            pa = length(q);
        }
        float dm = max(0.0, darkmatter - a * a * 0.001); // dark matter
        a *= a * a;                                      // add contrast
        if (r > 6) fade *= 1.0 - dm;                     // dark matter, don't render near
        v += fade;
        v += vec3(s, s * s, s * s * s * s) * a * brightness * fade; // coloring based on distance
        fade *= distfading;                                         // distance fading
        s += stepsize;
    }
    v = mix(vec3(length(v)), v, saturation); // color adjust
    fragColor = vec4(v * 0.01, 1.0);
}
