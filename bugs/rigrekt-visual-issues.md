# rigrekt Shader Visual Issues

## Problem
The `rigrekt` shader port rendered with:
1. Upside-down display
2. Jittery noisy mess around the edges of the view

## Status
- ✅ Fixed. Verified with a `grim` capture mid auto-hide window: opaque
  scene, correct orientation (glowing floor in the lower half), clean
  opaque-black letterbox bands, no skew, no GL errors in the journal.

## Resolution

Two independent root causes, both in `shaders/rigrekt.frag`:

1. **Upside-down + edge garble = broken coordinate conversion
   (roadmap tips 1 / 7).** Upstream uses the `res.y`-normalized family:
   `vec3 p = iResolution; u = (u+u-p.xy)/p.y;` with `u` = pixel fragCoord,
   giving x ∈ [−aspect, aspect]. The port translated that line literally
   with `p = vec3(aspect, 1, 1)` and `qt_TexCoord0`, producing
   `u = 2*qt_TexCoord0 − vec2(aspect, 1)` — x ∈ [−aspect, 2−aspect]. The
   view was therefore horizontally compressed by 1/aspect and shifted
   off-center (the "noisy mess at the edges"), and the mandatory y-flip
   for Qt's top-down texcoords was missing (the upside-down display).
   Fixed with the canonical `universeball.frag` block:
   `u = (qt_TexCoord0*2 − 1) * vec2(aspect, 1); u.y = −u.y;`.
   (Upstream's `vec3 p = iResolution` initializer was dead code — `p` is
   overwritten before first read — so `p` is now declared plain.)

2. **Desktop showing through = missing opaque alpha.** Shadertoy's canvas
   is opaque, so `mainImage`'s output alpha is ignored; upstream rigrekt
   never sets it (`o` starts at `vec4(0,0,0,0)` and every added term has
   a=0). Our layer-shell surface is composited *with* alpha, so the whole
   overlay — including the `abs(u.y) > .75` letterbox clip — was fully
   transparent and the desktop rendered underneath the shader. Every other
   port ends with `fragColor.a = 1.0`; rigrekt was the one that didn't.
   Fixed: the final path sets `o.a = 1.0` after the `tanh`, and the
   early-return clip now emits opaque `vec4(0,0,0,1)` instead of
   `o *= i` (which zeroed the alpha along with the rgb).

Both fixes are commented inline with `// jwz:` notes; the new alpha
gotcha is recorded as porting tip 18 in `docs/roadmap.md`.
