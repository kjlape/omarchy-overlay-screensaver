# Vendored: xscreensaver `hacks/` reference sources

Reference copies of source material from the **xscreensaver 6.16** release,
so this repo has no dependency on a checkout at
`/home/kjlape/dev/xscreensaver/xscreensaver-6.16` (or on downloading the
upstream tarball). Docs may reference the vendored paths directly instead of
an outside tree.

- **Provenance:** the xscreensaver 6.16 release tarball
  (`https://www.jwz.org/xscreensaver/`), paths mirrored from upstream
  `hacks/`.
- **These are reference/porting sources only** — nothing under `vendor/` is
  built, shipped, or enabled by the plugin. (The GLSL ports are re-implemented
  in `shaders/` and baked to `.qsb`; the Matrix C sources are cited by
  `moonshots/matrix-hacks.md` and would only ever run as *packaged*
  binaries, never from this tree.)
- **Keep original headers verbatim** — they carry the author, license, and
  (for GLSL) the shadertoy URL. Do not strip them when copying from here.

## Contents

### `hacks/glx/glsl/` — the Shadertoy-API GLSL collection

38 `.glsl` files / 32 distinct programs + upstream `README` (rendered
upstream via `../xshadertoy.c`). Porting sources for the shader content
mode; the full per-program status lives in `docs/roadmap.md` Phase 1.

### `hacks/xmatrix.c`, `hacks/glx/glmatrix.c` (+ `.man`) — the Matrix hacks

The two Matrix-themed screen savers, vendored for
[moonshots/matrix-hacks.md](../moonshots/matrix-hacks.md):

| File | Upstream path | Role |
|---|---|---|
| `hacks/xmatrix.c` | `hacks/xmatrix.c` | 2D X11 "digital rain" (the film monitors) |
| `hacks/glx/glmatrix.c` | `hacks/glx/glmatrix.c` | 3D fixed-function-GL rain (the title sequence) |
| `hacks/xmatrix.man`, `hacks/glx/glmatrix.man` | same | option documentation |
| `hacks/images/matrix1[2]b.png`, `matrix1[2].png` | `hacks/images/…` | xmatrix glyph atlases — 16×13 grids of 10×14 px cells; `1`/`2` = plain/glow map, `b` variants = black background |
| `hacks/images/matrix3.png` | `hacks/images/…` | glmatrix glyph atlas — 16×13 grid of 32×46 px cells (512×598) |

The `.c` files `#include` `images/gen/matrix*_png.h`, which upstream
*generates at build time* from these PNGs (bin2c). The generated headers are
deliberately not vendored — the PNGs are the source.

## License matrix (verified from file headers, 2026)

### GLSL collection

| Status | Files |
|---|---|
| CC0 (otaviogood) | `alienbeacon`, `elementalring`, `fluxcore`, `gimbalharmonics`, `protophore`, `skyline` |
| CC0 (mrange, some mixed embedded credits) | `batteredplanet`, `goldenapollian`, `stardome`, `logarithmiccircles`, `neontriangulator`, `truchetzoom`, `trainmandala`, `stripeytorus`, `selfreflect` |
| CC0 (mrange), multi-pass | `neongravity-0`/`-1` |
| MIT, relicensed by author for xscreensaver (Matt Vianueva) | `bestill0-0`…`bestill5-0`, `darktransit`, `downfall`, `noxfire`, `rigrekt`, `trizm`, `universeball` |
| MIT (other authors) | `hexplasma` (Nemerix), `polarnight` (supervitas), `prococean` (afl_ext), `starnest` (Kali) |
| ⚠️ No license statement in file — verify before porting/shipping | `bubblecolors`, `driftclouds` |
| ⚠️ xscreensaver in-house (GPL) — verify before porting/shipping | `amigajuggler` |
| ⚠️ Derivative of CC BY 3.0 original — attribution obligation | `synthwavecity` |

The ⚠️ rows are kept here for reference but are **do-not-ship** until
their licensing is resolved (tracked in `docs/roadmap.md`).

### Matrix hacks

| Item | License | Note |
|---|---|---|
| `xmatrix.c` (© 1999–2018 Jamie Zawinski) | jwz BSD-style notice ("Permission to use, copy, modify, distribute, and sell … provided that the above copyright notice appear in all copies…") | permissive, no copyleft; notice must travel with the file |
| `glmatrix.c` (© 2003–2018 Jamie Zawinski) | same | same |
| `matrix*.png` glyph atlases | **no per-file license header** | part of the xscreensaver distribution, whose convention is a per-file BSD-style notice (`README.hacking` requires one and states the GPL is incompatible with the rest of the tree). Practically the same umbrella, strictly the ⚠️ class — keep attribution if ever shipped, or avoid the images entirely (in-shader procedural glyphs). See `moonshots/matrix-hacks.md` §Licensing |

## Updating

Re-vendor by copying over from a newer xscreensaver tree and re-running the
header/license check documented in `docs/roadmap.md`:

```bash
cp -r <xscreensaver-tree>/hacks/glx/glsl/* vendor/xscreensaver/hacks/glx/glsl/
# Matrix hacks (paths mirror upstream):
cp -p <xscreensaver-tree>/hacks/xmatrix.c <xscreensaver-tree>/hacks/xmatrix.man \
      vendor/xscreensaver/hacks/
cp -p <xscreensaver-tree>/hacks/glx/glmatrix.c <xscreensaver-tree>/hacks/glx/glmatrix.man \
      vendor/xscreensaver/hacks/glx/
cp -p <xscreensaver-tree>/hacks/images/matrix*.png vendor/xscreensaver/hacks/images/
```
