// Title:  Rig Rekt
// Author: Matt Vianueva <diatribes@gmail.com>
// URL:    https://www.shadertoy.com/view/3XKfDV
// Date:   26-Feb-2026
// Desc:   Rig Rekt

// Relicensed as MIT License, by permission, 8-Mar-2026.

// Ported for Qt 6 ShaderEffect: mainImage(out vec4, fragCoord) became
// qt_TexCoord0 in [0,1]; iTime became the `time` uniform (seconds);
// iResolution became the `aspect` uniform (surface w/h). No iMouse or
// texture channels to drop. Coordinate conversion is the res.y-normalized
// family — see the jwz note in main(). Alpha is forced to 1.0: shadertoy
// ignores output alpha, but our layer-shell surface composites with it —
// a=0 made the whole overlay (incl. the letterbox clip) transparent, so
// the desktop showed through.

#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float aspect;
};

#define R(a) mat2(cos(a + vec4(0,33,11,0)))

float tunnel(vec3 p) {
    p = abs(p);
    return 4. - max(p.x, p.y/2.);
}

float box(vec3 p, float i) {
    p = abs(fract(p/i)*i - i/2.) - i*.08;
    return min(p.x, min(p.y, p.z));
}

float boxen(vec3 p) {
    float d = -9e9, i = 1e1;
    p.xy *= R(.5);
    for(; i > .2; i *= .2)
        p.xz *= R(i),
        d = max(d, box(p, i));
    return d;
}

float map(vec3 p) {
    return max(tunnel(p), boxen(p));
}

void main() {
    vec4 o = vec4(0,0,0,0);
    
    float i=0.,d=0.,s=0.,m=0.,k=0.;
    vec3 p; // jwz: upstream's init (iResolution) is dead — overwritten before read
    // jwz: was `vec3 p = iResolution; u = (u+u-p.xy)/p.y;` — the res.y-
    // normalized family. Correct Qt form is (2*uv - 1)*vec2(aspect,1);
    // writing (2*uv - vec2(aspect,1)) puts x in [-aspect, 2-aspect] —
    // compressed + shifted, garbled at the view edges — and the missing
    // y-flip turned the image upside down.
    vec2 u = (qt_TexCoord0*2.0 - 1.0) * vec2(aspect, 1.0);
    u.y = -u.y; // Qt texcoords run top-down; shadertoy runs bottom-up
    // jwz: was `o *=i; return;` — the letterbox clip must stay OPAQUE black;
    // o had a=0 there, which let the desktop show through the bands.
    if (abs(u.y) > .75) { fragColor = vec4(0,0,0,1); return; };

    vec3 D = normalize(vec3(u, 1));
    vec2 v = (.1*sin(time))+u + (u.yx*.8+.2-vec2(-1.,.1));

    for(o*=i; i++<64.;) {
        p = D * d;
        p.z += time;
        m = map(p);
        
        for(s = .01; s < .4; s += s )
            p += abs(dot(sin(.3*p.z+time+.7*p / s ), vec3(s/4.)));
        
        d += s = min(m, k = .005+.3*abs(p.y+1.5)),
        o += 6e1*vec4(1,1.2,1,0)*s
          + .5*vec4(1,1.1,1,0)/k;
    }
    
    o = tanh(o/1.3e3/exp(d/6e1)/length(v));
    o.a = 1.0; // jwz: shadertoy ignores alpha; the layer surface composites with it
    fragColor = o;
}