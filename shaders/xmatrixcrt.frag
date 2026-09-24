#version 440

/* xscreensaver, Copyright (c) 1999-2018 Jamie Zawinski <jwz@jwz.org>
 *
 * Permission to use, copy, modify, distribute, and sell this software and its
 * documentation for any purpose is hereby granted without fee, provided that
 * the above copyright notice appear in all copies and that both that
 * copyright notice and this permission notice appear in supporting
 * documentation.  No representations are made about the suitability of this
 * software for any purpose.  It is provided "as is" without express or
 * implied warranty.
 *
 * Matrix -- simulate the text scrolls from the movie "The Matrix".
 */

// EXPERIMENTAL FORK of xmatrix.frag — same glyph engine, dressed as a 90s
// CRT. The xmatrix engine below is the same math; this fork only adds a
// pre-stage and a post-stage around it:
//
//  pre  (top of main): barrel-curvature + H-sync wobble on qt_TexCoord0
//                      before the grid is built, so the glyph lattice
//                      itself bends like a picture tube; points that fall
//                      outside the curved raster render black (the bezel).
//  post (end of main): aperture-grille RGB mask (vertical phosphor
//                      stripes), scanlines at a fixed line count, vignette
//                      (corner falloff of a curved tube), a heavily
//                      attenuated mains-hum flicker, and a mild phosphor
//                      glow that fattens the glyphs' soft dots.
//
// Everything between pre and post is identical to xmatrix.frag — if the
// engine changes there, either mirror it here or accept that this is a
// frozen experiment. All CRT constants live in the CRT-TUNING block below.

// Reimplementation of upstream `hacks/xmatrix.c` (xscreensaver 6.16, vendored
// at vendor/xscreensaver/hacks/xmatrix.c) as a single stateless fragment
// shader — "Path A1" in moonshots/matrix-hacks.md. This is NOT a .glsl port:
// xmatrix is a 2D X11 raster program with per-frame C state (a glyph grid,
// one feeder per column, glow counters, spinners), so the algorithm had to be
// re-derived as a pure function of (time, aspect). The upstream license
// notice above covers the algorithm and the parameters taken from it.
//
// Adapted for Qt 6 ShaderEffect: no mainImage — the grid is laid out directly
// in qt_TexCoord0 (which already runs top-down, exactly what falling rain
// wants, so there is no y flip here; the glyph lattice is sampled upright).
// iTime → the `time` uniform (seconds); iResolution → `aspect` (w/h). The
// surface's pixel size is never needed: the grid is defined as ROWS rows of
// the screen height, so the look is resolution-independent (upstream used a
// fixed 10x14 px cell, i.e. more rows on a bigger screen).
//
// What is kept from upstream, and how it maps:
//   * cell grid, 10x14 px cells → ROWS rows, cell aspect 1.4 (CELL_AR).
//   * "they definitely scrolled a character at a time, not a pixel at a time"
//     (jwz's own comment) → the head row is floor()-quantized, so every column
//     jumps whole cells; nothing slides smoothly.
//   * one feeder per column with `remaining = 3 + random()%rows` glyphs and a
//     random 0..8-frame throttle → TRAILS independent parametric trails per
//     column, each with its own period/length/gap from hash(column, trail).
//     Per-trail constant speed + a slow sinusoidal surge stands in for the
//     per-step throttle (a stateless shader cannot accumulate random delays).
//   * `*density: 75` → the per-trail rest phase (`gap`) plus the 3-trail
//     sampling of each column; roughly a third of the grid is empty.
//   * `flip_images(state, True)` for MATRIX mode → the glyph lattice is
//     sampled mirrored in x (bitAt() does `GW-1-p.x`), which is what makes
//     upstream's rain look like an unreadable alien script rather than digits.
//   * PLAIN_MAP vs GLOW_MAP (see the two vendored atlases: the "glow" one is
//     the same glyphs drawn bolder, not a different color) → plain cells are
//     drawn with a smaller soft-dot radius, glowing cells a larger one.
//   * `cell->glow = random()%10` on random cells + `spinner` cells that redraw
//     every frame → the per-cell flash test and the spinner test below.
//   * glyph set: upstream's `matrix_encoding` is 26 glyphs — atlas slots
//     16..25 (digits 0-9) + 192..207 (the atlas' katakana row). The FONT
//     table below is 26 hand-drawn 5x7 bitmaps (10 digits + 16
//     katakana-inspired forms) I wrote for this file: the upstream atlases
//     carry no per-file license notice (vendor/xscreensaver/README.md marks
//     them the ⚠️ class), so nothing here is transcribed from them.
//
// Deliberate deviations:
//   * Upstream has no distance fade — every plain cell is the same #00AA00 and
//     the tail ends abruptly where the feeder's spaces erased it. The film's
//     screens (and upstream's own glmatrix) fade the tail, so `best` falls off
//     along the trail; it reads better and does not change the structure.
//   * The leading glyph is pushed toward white-green rather than merely bolder,
//     again matching the film rather than the X11 color limit.
//   * Dropped: tracePhone / knockKnock / pipe / pty / crack / nmap modes —
//     sequential and interactive behaviors, not part of the default look.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;   // seconds since shader show
    float aspect; // surface width / height
};

#define ROWS     30.0   // grid rows over the surface height
#define CELL_AR   1.4   // cell height / cell width (upstream cells are 10x14 px)
#define GW          5   // glyph lattice width
#define GH          7   // glyph lattice height
#define NG         26   // glyphs in FONT
#define TRAILS      3   // concurrent trails per column

// --- CRT-TUNING -----------------------------------------------------------
#define CRT_CURVE     0.16   // barrel strength (0 = flat panel)
#define CRT_WOBBLE    0.0022 // horizontal sync wobble amplitude (uv units)
#define CRT_SCANLINES 750.0  // scanline count over the surface height
#define CRT_SCAN_W    0.42   // scanline darkening depth (0..1)
#define CRT_MASK      1800.0 // aperture-grille stripes across the width
#define CRT_MASK_W    0.10   // grille color-modulation depth (0..1)
#define CRT_VIGNETTE  0.28   // corner falloff strength
#define CRT_FLICKER   0.015  // mains-hum flicker amplitude
#define CRT_GLOW      0.55   // extra phosphor glow radius added to bold glyphs

// Barrel-distorted, wobble-jittered screen coordinate + out-of-raster flag.
// Returns the uv the xmatrix grid should sample at; sets crtIn = 0 when the
// point falls outside the curved raster (black bezel).
float crtIn;
vec2 crtMap(vec2 uv, float t)
{
    // sync wobble: slow sine plus a faster ripple, like a drifting H-sync
    float wob = CRT_WOBBLE * (sin(t * 2.1) + 0.4 * sin(t * 23.7));
    vec2 c = (uv - 0.5) * vec2(2.0, 2.0);
    c.x += wob;
    float r2 = dot(c, c);
    c *= 1.0 + CRT_CURVE * r2;                 // barrel bulge
    crtIn = step(abs(c.x), 1.0) * step(abs(c.y), 1.0);
    return c * 0.5 + 0.5;
}

// --- hash: splitmix-style, integer key in, float [0,1) out -----------------
uint hash32(uint x)
{
    x += 0x9e3779b9u;
    x = (x ^ (x >> 16u)) * 0x21f0aaadu;
    x = (x ^ (x >> 15u)) * 0x735a2d97u;
    return x ^ (x >> 15u);
}

float hf(uint x) { return float(hash32(x)) * (1.0 / 4294967296.0); }

// --- the font: 26 glyphs, 5x7 px, row-major -------------------------------
// Rows 0..5 are packed 5 bits per row into .x (row 0 in bits 0..4), row 6 in
// the low 5 bits of .y. Bit i of a row is pixel i, left to right.
uvec2 fontGlyph(int i)
{
    switch (i) {
    case  0: return uvec2(0x233AE62Eu, 0x0Eu);  // 0
    case  1: return uvec2(0x084210C4u, 0x0Eu);  // 1
    case  2: return uvec2(0x0444422Eu, 0x1Fu);  // 2
    case  3: return uvec2(0x2304111Fu, 0x0Eu);  // 3
    case  4: return uvec2(0x108FCA98u, 0x08u);  // 4
    case  5: return uvec2(0x23083C3Fu, 0x0Eu);  // 5
    case  6: return uvec2(0x2317844Cu, 0x0Eu);  // 6
    case  7: return uvec2(0x0422221Fu, 0x02u);  // 7
    case  8: return uvec2(0x2317462Eu, 0x0Eu);  // 8
    case  9: return uvec2(0x110F462Eu, 0x06u);  // 9
    case 10: return uvec2(0x0884A7F0u, 0x02u);  // a
    case 11: return uvec2(0x08452A31u, 0x04u);  // i
    case 12: return uvec2(0x23084A1Fu, 0x0Eu);  // u
    case 13: return uvec2(0x2318C7F1u, 0x11u);  // e
    case 14: return uvec2(0x0427085Cu, 0x1Eu);  // o
    case 15: return uvec2(0x23151151u, 0x11u);  // ka
    case 16: return uvec2(0x24422B90u, 0x11u);  // ki
    case 17: return uvec2(0x022223E0u, 0x1Fu);  // ku
    case 18: return uvec2(0x0A98FE31u, 0x03u);  // ke
    case 19: return uvec2(0x0842289Eu, 0x06u);  // sa
    case 20: return uvec2(0x0842121Fu, 0x04u);  // shi
    case 21: return uvec2(0x0444422Eu, 0x0Eu);  // su
    case 22: return uvec2(0x2318C62Eu, 0x0Eu);  // so
    case 23: return uvec2(0x2442111Fu, 0x01u);  // ta
    case 24: return uvec2(0x2F9ACFB1u, 0x11u);  // ma
    case 25: return uvec2(0x239AC631u, 0x1Fu);  // wa
    default: return uvec2(0u);
    }
}

// One lattice pixel, x-mirrored (upstream flips the atlases in MATRIX mode).
float bitAt(uvec2 bits, ivec2 p)
{
    if (p.x < 0 || p.x >= GW || p.y < 0 || p.y >= GH)
        return 0.0;
    p.x = GW - 1 - p.x;
    uint row = (p.y < 6) ? ((bits.x >> (uint(p.y) * 5u)) & 31u) : bits.y;
    return float((row >> uint(p.x)) & 1u);
}

// Each set lattice pixel paints a soft dot; the dots overlap slightly, which
// is the low-resolution, blurry look jwz insists the film's glyphs had.
// `f` is continuous lattice space (bit i covers [i, i+1)), `radius` is in
// lattice pixels of one glyph row; x is stretched by CELL_AR because the
// lattice pixels are taller than they are wide.
float glyphCov(uvec2 bits, vec2 f, float radius)
{
    ivec2 b = ivec2(floor(f));
    vec2 o = f - vec2(b) - 0.5;
    float m = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float v = bitAt(bits, b + ivec2(dx, dy));
            if (v == 0.0)
                continue;
            vec2 d = vec2(CELL_AR, 1.0) * (o + vec2(float(dx), float(dy)));
            m = max(m, 1.0 - smoothstep(radius * 0.4, radius, length(d)));
        }
    }
    return m;
}

void main()
{
    // CRT pre-stage: sample the glyph engine at a barrel-curved, wobbling
    // coordinate; anything outside the raster is bezel-black.
    vec2 uv = crtMap(qt_TexCoord0, time);
    float cols = ROWS * aspect * CELL_AR;
    vec2 g = uv * vec2(cols, ROWS);
    ivec2 cell = ivec2(floor(g));
    vec2 local = g - vec2(cell);

    float best = 0.0;      // tail brightness of the winning trail
    float bestBold = 0.0;  // 1 = GLOW_MAP equivalent (bolder, hotter)
    uvec2 bestBits = uvec2(0u);

    for (int s = 0; s < TRAILS; s++) {
        uint key = uint(cell.x) * 31u + uint(s) * 100003u;
        float r0 = hf(key + 11u);       // period
        float r1 = hf(key + 27u);       // tail length
        float r2 = hf(key + 43u);       // phase offset
        float r3 = hf(key + 59u);       // surge offset
        float r4 = hf(key + 71u);       // rest fraction

        float period = 2.0 + 5.0 * r0;
        float tail = 5.0 + 16.0 * r1;
        float gap = 0.15 + 0.55 * r4;
        float phase = fract((time + r2 * period) / period);
        if (phase > 1.0 - gap)
            continue;                       // this feeder is idle
        phase /= 1.0 - gap;

        float span = ROWS + tail;
        float warp = phase + 0.035 * sin(6.283185 * (phase * 2.0 + r3));
        int head = int(floor(warp * span - tail));  // newest, lowest cell
        float d = float(head - cell.y);              // rows behind the head
        if (d < 0.0 || d > tail)
            continue;

        float b = pow(1.0 - d / max(tail, 1.0), 1.4);

        uint gk = uint(cell.x) * 7u + uint(s) * 499999u + uint(d) * 49u;
        // upstream: random cells briefly glow (hack_matrix's glow pass) — a
        // 6 Hz bucket so the flashes live for a few frames, not one.
        float flash = hf(gk + uint(floor(time * 6.0)) * 31u + 5u);
        // the newest cell glows, and upstream's glow counter survives one or
        // two more rows of travel (insert_glyph: glow = 1 + random()%2)
        float headGlow = clamp(1.0 - d / 1.6, 0.0, 1.0);
        float bold = max(headGlow, step(0.965, flash));
        // glyphs are locked to the trail (they scroll rigidly, as upstream's
        // column shift does); about a third of them mutate on a slow bucket.
        uint bucket = 0u;
        if (hf(gk + 17u) < 0.34)
            bucket = uint(floor(time * 1.7 + r2 * 7.0));
        int gi = int(hf(gk + bucket * 99991u + 3u) * float(NG)) % NG;

        if (b > best) {
            best = b;
            bestBold = bold;
            bestBits = fontGlyph(gi);
        }
    }

    // upstream: `spinners` (default 5) random cells redraw a new glyph every
    // frame with the glow map, and are re-seeded every few seconds.
    if (hf(uint(cell.x) * 3u + uint(cell.y) * 5u
           + uint(floor(time * 0.22)) * 77u + 9u) < 5.0 / (ROWS * cols)) {
        best = 1.0;
        bestBold = 1.0;
        bestBits = fontGlyph(int(hf(uint(cell.x) * 13u + uint(cell.y) * 29u
                                    + uint(floor(time * 24.0)) * 991u + 7u)
                                 * float(NG)) % NG);
    }

    vec2 margin = vec2(0.09, 0.035);
    vec2 p = (local - margin) / (1.0 - 2.0 * margin);
    float cov = glyphCov(bestBits, p * vec2(float(GW), float(GH)),
                         mix(0.72, 1.05, bestBold));

    vec3 green = vec3(0.0, 0.667, 0.0);      // upstream *foreground: #00AA00
    vec3 hot = vec3(0.72, 1.0, 0.75);        // the film's leading glyph
    vec3 col = mix(green, hot, bestBold) * cov * (0.3 + 0.7 * best);

    // ---- CRT post-stage ----
    // Phosphor glow: re-cover the glyph with a fatter, dimmer dot and add it
    // back on top — the halo a bloomed tube puts around bright glyphs.
    float glowCov = glyphCov(bestBits, p * vec2(float(GW), float(GH)),
                             mix(0.72, 1.05, bestBold) + CRT_GLOW);
    col += vec3(0.0, 0.35, 0.05) * glowCov * (0.10 + 0.20 * bestBold)
         * (0.3 + 0.7 * best);

    // Aperture grille: vertical phosphor stripes modulate each channel
    // slightly out of phase, so greens lean cyan/magenta at the pixel level.
    float mx = uv.x * CRT_MASK;
    float ph = fract(mx) * 3.0;
    vec3 grille = vec3(step(1.0, ph),
                       1.0 - 0.5 * abs(ph - 2.0) * step(ph, 3.0) * step(1.0, ph),
                       step(2.0, ph));
    grille = mix(vec3(1.0), normalize(grille + 0.35), CRT_MASK_W * 3.0);
    col *= grille;

    // Scanlines: dark bands at a fixed line count (resolution-independent;
    // smoothstep keeps them from aliasing into moiré).
    float scan = 0.5 + 0.5 * sin(uv.y * CRT_SCANLINES * 6.283185);
    col *= 1.0 - CRT_SCAN_W * (1.0 - smoothstep(0.15, 0.85, scan));

    // Vignette: corners of a curved tube catch less beam.
    vec2 vc = (qt_TexCoord0 - 0.5) * 2.0;
    col *= 1.0 - CRT_VIGNETTE * dot(vc, vc) * 0.5;

    // Mains-hum flicker: a fast ~100 Hz-ish beat plus a slow brightness
    // wander, both heavily attenuated so it reads as a tube, not a strobe.
    col *= 1.0 + CRT_FLICKER * (sin(time * 628.3) * 0.5 + sin(time * 3.7) * 0.5);

    col *= crtIn;                            // bezel: black outside the tube
    fragColor = vec4(col, 1.0);              // tip 18: the surface composites alpha
}
