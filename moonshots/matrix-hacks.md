# Feasibility: the Matrix-themed xscreensaver hacks

Assessment of the two "Matrix" hacks vendored at
[`vendor/xscreensaver/hacks/`](../vendor/xscreensaver/README.md) (from the
xscreensaver 6.16 release) and how portable they are to this
overlay-screensaver stack. Verified 2026-09-24 against the 6.16 sources.

Not implemented. Research + comparison + options only; the recommendation at
the end is a suggested order of operations, not a commitment.

## Inventory

Exactly two hacks are Matrix-themed (paths relative to
`vendor/xscreensaver/`):

| Hack | File | Lines | Renderer | What it simulates |
|---|---|---|---|---|
| `xmatrix` | `hacks/xmatrix.c` | 1914 | 2D X11 (no GPU) | the computer monitors *in* the film — 2D digital rain |
| `glmatrix` | `hacks/glx/glmatrix.c` | 1076 | fixed-function OpenGL 3D | the 3D title-sequence rain |

Both by Jamie Zawinski, both carry the standard jwz BSD-style notice.
Everything else in the 6.16 tree that matches "matrix" (`binaryhorizon`,
`binaryring`, `m6502`, the `matrix*.png` assets, "transform matrix" comments
in `glx/*`) is unrelated.

## Comparison

### Rendering stack

- **xmatrix** is pure X11 raster: it pre-renders glyphs into `Pixmap`s from
  the vendored PNG assets (`hacks/images/matrix1[2][b].png`) and blits cells
  with `XCopyArea`, erasing with `XFillRectangle`. Two glyph maps (plain +
  "glow"), four asset variants — 16×13 grids of 10×14 px cells. No OpenGL
  anywhere; runs happily on a 1-bit display in principle.
- **glmatrix** is legacy immediate-mode GL: `glBegin(GL_QUADS)` textured
  quads, a GLX context, one texture atlas (`hacks/images/matrix3.png`,
  512×598, 16×13 grid of 32×46 px cells, padded to a power of two, alpha
  taken from the green channel, glyphs flipped per-pixel in software at
  load). It does a `qsort` of all strips per frame for depth order and
  relies on additive blending (`GL_SRC_ALPHA, GL_ONE`) so overlaps brighten.

### Algorithm and state

Both are stateful C programs with persistent per-frame state — neither is a
per-frame function of `(time, resolution)`:

- **xmatrix** keeps a character grid (`m_cell` per column×row, plus a second
  "background" buffer), one "feeder" per column, spinners, glow counters.
  Default mode (`Matrix`): feeders drop glyphs; cells glow and fade;
  spinners flicker random glyphs. Density controls the fill percentage.
  Extra behaviors on top of the look: `tracePhone` (a phone number scrolls
  through the rain, then the screen reveals backwards), `knockKnock`
  ("SYSTEM FAILURE" box), `crack` mode, `pipe`/`pty` input (feeds arbitrary
  text — even `xscreensaver-text`), and top/bottom/both insertion.
- **glmatrix** keeps N "strips" (vertical glyph columns) in a 3D arena
  (70×70×35): per-strip random velocity (smoothed `BELLRAND`), a bright
  "spinner" head glyph that cycles, a brightness wave (period 22), glyph
  arrays per strip. Camera: fixed view + optional slow rotation + periodic
  switches between preset "nice views" + device rotation. Modes: Matrix,
  binary, hex, DNA, ASCII, and `clock` (renders the local time into a
  random strip, once per ~5 strips).

### Footprint and dependencies

| | xmatrix | glmatrix |
|---|---|---|
| Needs | X11 client lib | X11 + GLX |
| xscreensaver daemon | not required | not required |
| Assets | 4 small PNGs (160×182) | 1 PNG (512×598) |
| CPU (software) | trivial | moderate (swrast) |
| `-window-id` (6.16) | option is in the Xrm table but **dead** — never read anywhere in the tree; confirms the moonshot's "it never worked right / removed" note | same |
| Packaged binary on this machine | **not installed** (no `xscreensaver` package) | same |

Bottom line of the comparison: **xmatrix is the simpler, lighter, more
iconic one** (the 2D rain everyone means by "matrix screensaver"), with more
quirky behaviors but none of them load-bearing for the look. **glmatrix is
the prettier 3D one** and the harder port, in both possible directions.

## Fit against this stack

The plugin's content modes are: (a) static image, (b) one in-process GLSL
fragment shader in a Qt `ShaderEffect` (baked `.qsb`, uniforms `time`/
`aspect`, stateless per frame, no X11 or GL context of its own), and (c) the
unimplemented [Xvfb + frame-capture moonshot](xscreensaver-hacks.md).

**"No changes to their source code" is impossible in mode (b)** — and that's
not a licensing or effort problem, it's a category mismatch:

- `xmatrix.c` draws via X11 raster calls against pixmaps it owns. There is no
  shader form of it; it must be *reimplemented* in GLSL (mode b) or *executed*
  as a program (mode c).
- `glmatrix.c` is fixed-function desktop GL (`glBegin`/`glEnd`, GLX). Qt
  `ShaderEffect` runs a single fragment stage on the scene graph's own
  context — immediate-mode quads don't live there either.

So every path is either "reimplement the algorithm as a fragment shader" or
"run the real binary somewhere and capture its frames". The fork-the-C-source
option (new Wayland/EGL backend for jwz's framework, plus a fixed-function →
modern-GL rewrite for glmatrix) is a full port with the worst ergonomics
(jwz's framework has no Wayland backend, and the framework itself —
`screenhack.c`, `xlockmore` — would have to come along), and is ruled out.

## Path A — reimplement the look as a GLSL fragment shader

The established port path (`shaders/`, `knownShaders` in `Service.qml`, `qsb`
bake). Both hacks' *signature visuals* are expressible as stateless per-frame
functions, which is exactly what the shader mode wants:

- Rain = per-column parameters derived from `hash(column)`; head position =
  pure function of `time` (parametric fall with respawn); tail = brightness
  as a function of distance behind the head; per-cell glyph =
  `hash(column, cellIndex, floor(time / flipInterval))`.
- Flicker/spinners = re-hash on a time bucket.
- Additive glow = the stack already outputs premultiplied color; "additive
  blending can be achieved by outputting zero in the alpha channel" (Qt
  docs), matching upstream's `GL_SRC_ALPHA, GL_ONE` behavior.

**The enabler that makes A high-fidelity:** Qt 6 `ShaderEffect` maps a QML
`Image` property to a `sampler2D` in the fragment shader (verified against
the Qt 6 `ShaderEffect` docs — the documented example is literally
`property variant src: Image{...}` sampled as `layout(binding=1) uniform
sampler2D src`). So the **upstream glyph atlas PNGs can be vendored and
sampled directly**, giving the exact low-res film font (jwz noted the film's
glyphs were deliberately low-resolution and blurry — the 10×14 px cells are
the aesthetic). Fallback if we want zero asset dependencies: generate
blocky glyphs procedurally in-shader (hash-based pixel grid); slightly less
faithful, but fine.

### A1: xmatrix → GLSL ("xmatrix" shader)

- **Scope:** default `Matrix` mode — falling columns, glowing head, fading
  tail, random glyphs, per-column random speed/density/length, top/bottom
  insertion. ~80–150 lines of fragment GLSL + vendored `matrix1b.png` (plain)
  / `matrix2b.png` (glow) as two `Image`-backed samplers, or one atlas with a
  glow pass.
- **Lost:** `tracePhone`, `knockKnock`, `pipe`/`pty`, interactive
  density changes — sequential/interactive behaviors that don't fit a
  stateless shader. These are easter-egg behaviors, not the look.
- **Fidelity:** ~90% of the visual essence; nobody's going to notice the
  missing phone number.
- **Effort:** 1–2 days including the normal bake/restart/capture test loop.
  Easiest port on the roadmap table, arguably easier than `starnest`'s was
  (no 3D, no orbit math).

### A2: glmatrix → GLSL ("glmatrix" shader)

- **Scope:** 3D rain tunnel — perspective-mapped strips, textured glyph
  sprites, wave brightness, camera rotation. The `qsort` depth sort drops out
  for free because upstream already blends additively (order-independent).
  The hard part is making the strip z-motion a pure function of `time`
  (parametric fall + respawn + per-strip randoms from `hash(strip)`), plus
  the projection math (arena 70×70×35, camera at the near end).
- **Fidelity risk:** medium. A per-pixel "which strip does this column
  belong to" (2.5D) approximation is the safe route; per-pixel per-sprite
  ray-marching against a few dozen strips is the expensive route. The
  rotating 3D look is subjective to nail.
- **Effort:** 3–5 days + tuning. The hardest thing in this report.
- **Verdict:** do it only if Path B falls through and the 3D look is wanted.

## Path B — run the real, unmodified binaries via the Xvfb moonshot

Zero source changes, zero code copying: the plugin spawns the **packaged**
`xmatrix`/`glmatrix` binaries (Debian/Ubuntu `xscreensaver` package →
`/usr/lib/xscreensaver/…`) inside the offscreen X stage from
[xscreensaver-hacks.md](xscreensaver-hacks.md):

```
Xvfb :99 -screen 0 1920x1080x24          # GLX only needed for glmatrix
DISPLAY=:99 /usr/lib/xscreensaver/xmatrix -root -density 75   # no GLX needed
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 /usr/lib/xscreensaver/glmatrix -root
ffmpeg -f x11grab … → frames → QML Image swap in the overlay (moonshot MVP)
```

These two hacks are the *ideal pilots* for that moonshot:

- They need no daemon, no `-window-id` (dead in 6.16 anyway), and no
  xscreensaver configuration; both spawn standalone with `-root`.
- `xmatrix` needs **no GLX at all** — the pipeline can be built and validated
  with plain Xvfb + 2D capture, which is the cheap half of the moonshot.
  `glmatrix` then only adds the `LIBGL_ALWAYS_SOFTWARE` GLX variant.
- Both are light enough that the moonshot's 1080p/25fps PNG-frame cap is not
  the bottleneck (xmatrix: trivial; glmatrix: moderate under swrast).

- **Cost:** the pipeline doesn't exist yet. Building the moonshot MVP
  (Xvfb lifecycle + `x11grab` + PGID hygiene + `show-hack`/`list-hacks` IPC +
  QML frame-swap `Image`) is the work item — estimate **3–5 days**, after
  which *every* X11 hack in the collection becomes reachable, not just these
  two.
- **Prerequisite:** `xscreensaver` package installed (it is **not** on this
  machine today; `apt install xscreensaver` on Omarchy/Debian).
- **Fidelity:** 100% — it's the actual programs, including tracePhone, clock
  mode, knock-knock, pipe input.
- **Ongoing cost:** a resident Xvfb + ffmpeg while shown (kill-ladder hygiene
  per the moonshot keeps the recovery guarantee).

## Path C — fork the C sources, write a Wayland backend — rejected

xmatrix's X11 draw calls would have to be rewritten against a wlroots
layer-shell buffer (custom glyph blitting), and glmatrix's fixed-function GL
has no desktop-GL home on a Wayland EGL surface (ES 3.0 only) — i.e. a full
port plus carrying the `screenhack`/`xlockmore` framework. Worse than A or B
on every axis. (Kept in this report so the option is visibly considered.)

## Licensing

Verified from the vendored 6.16 sources
(`vendor/xscreensaver/hacks/`, 2026-09-24):

| Item | License | Implication |
|---|---|---|
| `xmatrix.c` | jwz BSD-style notice ("Permission to use, copy, modify, distribute, and sell … provided that the above copyright notice appear in all copies…"), © 1999–2018 Jamie Zawinski | Free to copy, modify, ship. Notice must travel with the file. No copyleft. |
| `glmatrix.c` | same notice, © 2003–2018 | same |
| Glyph atlas PNGs (`matrix1.png`, `matrix1b.png`, `matrix2.png`, `matrix2b.png`, `matrix3.png`) | **No per-file license header** — distributed inside the xscreensaver tarball, whose convention is a per-file BSD-style notice (`README.hacking` *requires* one in every source file and states the GPL is incompatible with the rest of the tree) | Same practical umbrella, but strictly there is no explicit notice on the images. Treat as the repo's ⚠️ class: keep attribution ("from xscreensaver, Jamie Zawinski") and, if being extra safe, generate the atlas procedurally in-shader instead (the in-shader procedural option exists anyway). |
| Packaged binaries (Path B) | Whatever the distro package ships, unmodified | No copying at all — we only `exec` a binary the user installs. Nothing to redistribute; no obligations on the plugin beyond "requires `xscreensaver` package". |

Cross-check: this matches the license analysis already in
[moonshots/xscreensaver-hacks.md](xscreensaver-hacks.md#licensing-verified-against-the-616-source-sep-2026)
and [vendor/xscreensaver/README.md](../vendor/xscreensaver/README.md)
(jwz's code is deliberately permissive, no GPL contamination).

For any ported shader, the provenance/attribution convention from
`docs/roadmap.md` applies: upstream header + adaptation notes in the `.frag`.

## Recommendation

1. **Ship A1 first** — `xmatrix`'s default rain as a GLSL port in `shaders/`.
   One `knownShaders` entry, vendored glyph atlas (or procedural glyphs),
   1–2 days. It's the most recognizable "matrix" look, it fits the existing
   stack with zero new infrastructure, and it de-risks the atlas-sampler
   pattern (Image → `sampler2D`) that A2 and future ports would reuse.
2. **Use these two hacks as the moonshot pilot** — when the Xvfb pipeline
   gets built, `xmatrix` validates the GLX-free half and `glmatrix` validates
   the swrast-GLX half. That buys the *actual* programs (100% fidelity, all
   easter-egg modes) and every other X11 hack behind the same door.
3. **Defer A2** (GLSL glmatrix) — only if the 3D look is specifically wanted
   and Path B doesn't materialize.

## Open details (verify at implementation time, not now)

- `Image`-as-`sampler2D` through **Quickshell's** Qt build (the Qt docs say
  yes; this repo's `ShaderEffect` usage hasn't exercised it yet — confirm
  with a 5-line scratch shader on the dev install before committing to the
  vendored-atlas design).
- Premultiplied-color handling of the 8-bit colormap PNGs through the
  sampler (upstream took alpha from the green channel itself; check how a
  straight-alpha PNG lands and adjust with a one-line shader fix if needed).
- `qsb` bake of a shader with two samplers (binding 1 and 2).
