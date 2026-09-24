# Roadmap: Xscreensaver Port

## Overview

Goal: expand the `kjlape.overlay-screensaver` from a single ported GLSL hack (`starnest`) to a library of **portable, per-frame fragment shaders** that run in-process inside the `ShaderEffect` overlay surface.

This is the **complement path** from `moonshots/xscreensaver-hacks.md`: no Xvfb, no child-process tree, no Wayland gaps — everything is a QML `ShaderEffect` bound to the existing `PanelWindow`/`WlrLayer.Top` surface.

The "run all 270 hacks" moonshot via Xvfb is tracked separately under `moonshots/xscreensaver-hacks.md`. This document is strictly for the **shader-based subset** (~20–50 programs) that ports directly to Qt 6 `ShaderEffect`.

## Status

- [x] Phase 0: porting recipe established (`starnest`)
- [] Phase 1: xscreensaver `glx/glsl/` collection (32 programs, 38 files — verified against local 6.16 tree)
- [] Phase 2: curated shadertoy.com picks (30–50 programs)
- [ ] Phase 3: config + UX integration
- [ ] Phase 4: tooling (batch conversion, shader gallery)

---

## Phase 0: Recipe (DONE)

`starnest` is ported. The recipe is proven:

1. Download GLSL source
2. Rewrite for Qt 6 `ShaderEffect`:
   - Input: `qt_TexCoord0` (location 0)
   - Uniforms: `time` (seconds), `aspect` (w/h)
   - Output: `fragColor`
   - Add minimal vertex stage (`qt_TexCoord0` passthrough)
3. Bake both stages with `qsb`:
   ```bash
   qsb --glsl shaders/<name>.frag -o shaders/<name>.frag.qsb
   qsb --glsl shaders/<name>.vert -o shaders/<name>.vert.qsb
   ```
4. Register in `Service.qml` `knownShaders` map
5. Test: `omarchy-overlay-screensaver showShader <name>`

**Gotchas** (documented in ARCHITECTURE.md):
- NVIDIA linker requires explicit-location vertex output
- QSL hot-reload may serve stale compiles — use `omarchy-shell shell rescanPlugins`
- `starnest` used `iMouse` (dropped for screensaver use); replace with `time`-driven animation

---

## Phase 1: xscreensaver `glx/glsl/` Collection (32 programs)

These ship with xscreensaver at `hacks/glx/glsl/` — **verified against the local 6.16 tree at `/home/kjlape/dev/xscreensaver/xscreensaver-6.16`** (38 `.glsl` files: some hacks are multi-pass). They are the **safest** starting point — already vetted and, in most cases, explicitly licensed by the upstream shadertoy authors.

### Target programs

All files are single-pass `mainImage` shaders unless noted. Verified from the local tree:

| # | File(s) | Program | Author (license) | Notes | Priority |
|---|---|---|---|---|---|
| 1 | `starnest.glsl` | Star Nest | Kali (MIT) | ✅ Done | ✅ |
| 2 | `topologica.glsl` | Topologica | ? (see file header) | uses `iMouse` — replace with time-driven animation | 🔴 High |
| 3 | `stardome.glsl` | Stardome | mrange (CC0) | 300 lines | 🔴 High |
| 4 | `universeball.glsl` | Universe Ball | Matt Vianueva (MIT, relicensed) | 43 lines, trivial port | 🔴 High |
| 5 | `bubblecolors.glsl` | Bubble Colors | Matt Vianueva (license **unverified** — no statement in file) | 23 lines | 🔴 High |
| 6 | `downfall.glsl` | Downfall | Matt Vianueva (MIT, relicensed) | 35 lines | 🔴 High |
| 7 | `trizm.glsl` | Trizm | Matt Vianueva (MIT, relicensed) | 64 lines | 🔴 High |
| 8 | `hexplasma.glsl` | Hex Plasma | Nemerix (MIT) | 57 lines | 🔴 High |
| 9 | `rigrekt.glsl` | Rigrekt | Matt Vianueva (MIT, relicensed) | 61 lines | 🟡 Medium |
| 10 | `batteredplanet.glsl` | Battered Planet | mrange (CC0) | 355 lines, raymarched | 🟡 Medium |
| 11 | `goldenapollian.glsl` | Golden Apollian | mrange (CC0) | 383 lines | 🟡 Medium |
| 12 | `selfreflect.glsl` | Self Reflect | mrange (CC0, mixed credits) | borrowings under WTFPL/MIT/unknown — check embedded credit lines | 🟡 Medium |
| 13 | `logarithmiccircles.glsl` | Logarithmic Circles | mrange (CC0) | 96 lines | 🟡 Medium |
| 14 | `neontriangulator.glsl` | Neon Triangulator | mrange (CC0, mixed credits) | 303 lines | 🟡 Medium |
| 15 | `truchetzoom.glsl` | Truchet Zoom | mrange (CC0, mixed credits) | 234 lines | 🟡 Medium |
| 16 | `trainmandala.glsl` | Train Mandala | mrange (CC0) | 121 lines | 🟡 Medium |
| 17 | `stripeytorus.glsl` | Stripey Torus | mrange (CC0, mixed credits) | 200 lines, raymarched | 🟡 Medium |
| 18 | `polarnight.glsl` | Polar Night | supervitas (MIT, relicensed) | 269 lines, raymarched terrain | 🟡 Medium |
| 19 | `prococean.glsl` | Procedural Ocean | afl_ext (MIT) | uses `iMouse` — steer with time | 🟡 Medium |
| 20 | `driftclouds.glsl` | Drift Clouds | drift (license **unverified** — no statement in file) | 127 lines | 🟡 Medium |
| 21 | `synthwavecity.glsl` | Synthwave City | 3w36zj6 (derivative; original **CC BY 3.0**) | attribution required — deprioritize for license reasons | 🟢 Lower |
| 22 | `elementalring.glsl` | Elemental Ring | otaviogood (CC0) | uses `iMouse` | 🟢 Lower |
| 23 | `alienbeacon.glsl` | Alien Beacon | otaviogood (CC0) | 424 lines, uses `iMouse` | 🟢 Lower |
| 24 | `protophore.glsl` | Protophore | otaviogood (CC0) | **3 texture channels** (`iChannel0–2`) — needs QML-supplied textures | 🟢 Lower |
| 25 | `gimbalharmonics.glsl` | Gimbal Harmonics | otaviogood (CC0) | **3 texture channels**, uses `iMouse` | 🟢 Lower |
| 26 | `fluxcore.glsl` | Flux Core | otaviogood (CC0) | 681 lines, uses `iMouse` — heavy | 🟢 Lower |
| 27 | `skyline.glsl` | Skyline | otaviogood (CC0) | 888 lines, **6 texture channels**, uses `iMouse` — hardest in the set | 🟢 Lower |
| 28 | `noxfire.glsl` | Noxfire | Matt Vianueva (MIT, relicensed) | 79 lines | 🟢 Lower |
| 29 | `darktransit.glsl` | Dark Transit | Matt Vianueva (MIT, relicensed) | 381 lines | 🟢 Lower |
| 30 | `neongravity-0.glsl`, `neongravity-1.glsl` | Neon Gravity | mrange (CC0, mixed credits) | **2-pass** (pass 0 uses 11 texture refs); needs framebuffer ping-pong or merged single-pass rewrite | 🟢 Lower |
| 31 | `bestill0-0.glsl` … `bestill5-0.glsl` | Bestill | Matt Vianueva (MIT, relicensed) | **6-pass** — needs multi-`ShaderEffect` chain; largest single effort | 🟢 Lower |
| 32 | `amigajuggler.glsl` | Amiga Juggler | Brian Bernstein, written for xscreensaver (license: xscreensaver's, effectively GPL — **verify before porting**) | 479 lines, single self-contained `mainImage` (the other `mainImage` match is a comment), procedural ray tracer | 🟢 Lower |

### Verified-facts summary (2026 check against 6.16 tree)

- **Count**: 38 `.glsl` files / 32 distinct programs under `hacks/glx/glsl/`.
- **Multi-pass** (filename pattern `<pass>` or `N-M.glsl`): `bestill` (6 passes), `neongravity` (2 passes). Everything else is single-pass.
- **Texture users** (need QML `source` images or rework): `gimbalharmonics`, `neongravity` (pass 0), `protophore`, `skyline`.
- **`iMouse` users** (replace with time-driven values): `alienbeacon`, `elementalring`, `fluxcore`, `gimbalharmonics`, `prococean`, `protophore`, `skyline`, `starnest` (already handled), `topologica`.
- **License-block absent / ambiguous**: `bubblecolors`, `driftclouds` (no license statement — verify with author or upstream xscreensaver before shipping), `amigajuggler` (xscreensaver-in-house, effectively GPL), `synthwavecity` (derivative of a CC BY 3.0 original — attribution obligation).
- **Everything else** carries an explicit CC0/MIT header (several Matt Vianueva shaders were explicitly relicensed to MIT by the author for xscreensaver inclusion).

### Per-program task checklist

For each of the remaining 31 programs (source is already local at
`/home/kjlape/dev/xscreensaver/xscreensaver-6.16/hacks/glx/glsl/<name>.glsl`):

```
[ ] 1. Copy the GLSL source from the local 6.16 tree
[ ] 2. Create shaders/<name>.vert (qt_TexCoord0 passthrough)
[ ] 3. Port shaders/<name>.frag:
       - Rename iTime → time
       - Rename iResolution → aspect  
       - Input: qt_TexCoord0
       - Output: fragColor
       - Drop iMouse dependency (replace with time-driven values)
       - Ensure uniform block is correct
       - Multi-pass files (bestill N-M, neongravity N): chain ShaderEffects
             with a texture between passes, or merge into one pass if feasible
       - Texture-channel users: supply textures via QML source properties
             or strip the texture dependency
[ ] 4. Bake: qsb --glsl shaders/<name>.frag -o shaders/<name>.frag.qsb
[ ] 5. Bake: qsb --glsl shaders/<name>.vert -o shaders/<name>.vert.qsb
[ ] 6. Add to knownShaders in Service.qml:
       readonly property var knownShaders: ({ ..., "<name>": "shaders/<name>.frag.qsb" })
[ ] 7. Test: omarchy-overlay-screensaver showShader <name>
[ ] 8. Preserve the upstream license header verbatim in the .frag file
```

### Estimated effort

- Simple single-pass, no-texture shaders (the ~20 short ones): ~15–30 min each including visual testing
- Multi-pass (`bestill` 6-pass, `neongravity` 2-pass): hours each — need chained `ShaderEffect`s
- Texture-channel users (`skyline`, `protophore`, `gimbalharmonics`, `neongravity` pass 0): medium — QML can feed textures to `ShaderEffect`, but assets must ship with the plugin
- `skyline` (888 lines, 6 textures, `iMouse`) is the largest single effort — keep last

### Gotchas to watch for (verified from 6.16 sources)

- **Multi-pass hacks** (`bestill0-0`…`bestill5-0`, `neongravity-0`/`-1`): file naming `N-M.glsl` = pass N, variant M. A single `ShaderEffect` only does one pass — chain via intermediate texture or merge passes.
- **Texture users** (`skyline`, `protophore`, `gimbalharmonics`, `neongravity` pass 0): `iChannel0–2` references must be replaced with QML `source`-property textures (plugin must bundle the assets) or the code rewritten texture-free.
- **`iMouse` users** (9 shaders, listed above): replace with time-derived motion as done for `starnest`.
- **License-ambiguous** (`bubblecolors`, `driftclouds`, `amigajuggler`, `synthwavecity`): do not ship until verified. `amigajuggler` is xscreensaver-in-house (GPL); `synthwavecity` derives from a CC BY 3.0 original.
- **Heavy raymarchers** (`batteredplanet`, `polarnight`, `stripeytorus`, `selfreflect`, `fluxcore`, `skyline`): verify frame rate on the actual overlay hardware; may need iteration/step caps.

---

## Phase 2: Curated shadertoy.com Picks (30–50 programs)

Beyond xscreensaver's built-in GLSL hacks, the shadertoy.com collection offers hundreds of programs. We pick 30–50 based on:

- **License**: MIT, CC0, permissive. Skip GPL.
- **Portability**: pure fragment shader, no external textures/assets, <200 LOC
- **Performance**: no heavy raymarching, no large lookup tables
- **Aesthetic variety**: mix of fractals, volumes, particles, noise, geometry, abstraction
- **Author reputation**: programs by top shadertoy authors tend to be self-contained and well-written

### Criteria

| Category | Target count | Examples (from Phase 1, already vetted) |
|---|---|---|
| Fractals / iteration | 6 | topologica, goldenapollian, logarithmiccircles, truchetzoom, hexplasma, trizm |
| Volumetric / noise | 5 | stardome, batteredplanet, driftclouds, fluxcore, polarnight |
| Particles / dots | 5 | universeball, bubblecolors, downfall, rigrekt, trainmandala |
| Geometry / abstract | 5 | alienbeacon, elementalring, gimbalharmonics, protophore, selfreflect |
| Math / abstract | 5 | neontriangulator, stripeytorus, noxfire, truchetzoom, synthwavecity |
| Miscellaneous / unique | 5 | skyline, amigajuggler, prococean, neongravity, darktransit |

(Plus fresh picks from shadertoy.com beyond the xscreensaver set — same porting rules apply.)

### shadertoy.com search filters

When selecting programs:

```
- Use: https://www.shadertoy.com
- Filters: GLSL shaders (not pixel shaders, not vertex-only)
- Sort: by "most upvotes" — community-vetted
- Filter by collection: Fractals, Volumetric, Particles, Space, Abstract
- Skip: programs that load textures, use random seeds without `iTime`, or are >400 LOC
```

### Porting template

Each new shader gets its own set of files:

```
shaders/
├── <slug>.vert              # 4-line qt_TexCoord0 passthrough
├── <slug>.vert.qsb         # baked
├── <slug>.frag              # ported from shadertoy
├── <slug>.frag.qsb         # baked
└── <slug>.md              # attribution note (optional)
```

**Vertex stage template**:
```glsl
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;
void main() { qt_TexCoord0 = qt_TexCoord0; }
```

**Porting checklist per program**:
```
[ ] 1. Read the shadertoy source code (view page → "View Code" tab)
[ ] 2. Verify license (MIT / CC0 / permissive header)
[ ] 3. Save source → shaders/<slug>.frag
[ ] 4. Rename inputs:
       - main() → no change
       - in vec2 mainImage → use qt_TexCoord0 directly
       - vec2 uv = mainImage / iResolution → vec2 uv = qt_TexCoord0;
       - float time = iTime / 60.0 → float time = iTime;  (already seconds in Qt)
       - vec2 res = iResolution → float aspect = width / height;  (passed from QML)
       - Remove iMouse usage or replace with time-derived value
[ ] 5. Create shaders/<slug>.vert (4 lines above)
[ ] 6. Bake both: qsb --glsl shaders/<slug>.frag -o shaders/<slug>.frag.qsb
[ ] 7. Register in Service.qml knownShaders
[ ] 8. Test: showShader <slug>
```

---

## Phase 3: Config + UX Integration

Once you have a library of shaders, wire them up:

### 3.1. `shell.json` config

Current config already supports `shader: "starnest"`. This should work for any ported name:

```json
{
  "id": "kjlape.overlay-screensaver",
  "enabled": true,
  "config": {
    "image": "",
    "shader": "stardome"
  }
}
```

### 3.2. `knownShaders` as a resource file (optional)

For 30+ shaders, inline map in Service.qml gets unwieldy. Consider:

```
shaders/
├── registry.json    # {"stardome": {"frag": "shaders/stardome.frag.qsb", "label": "Stardome"}, ...}
├── <slug>.vert
├── <slug>.frag
├── <slug>.frag.qsb
└── <slug>.vert.qsb
```

Load with `Resource.loadJson()` at startup. This defers to a later refactor; inline map is fine for <20 shaders.

### 3.3. List of available shaders

CLI command (extension of current `status()`):

```
omarchy-shell overlayscreensaver list-shaders
```

Returns: `["starnest", "stardome", "topologica", ...]`

Or add `listShaders()` to `IpcHandler`.

### 3.4. Auto-discovery / registry

When new shader files are dropped in `shaders/`, auto-register them:
```cpp
// Service.qml, on loaded:
Component.onLoaded: {
  for (var key in fileSystem.getDirectory("/home/<user>/dev/kjlape/omarchy-overlay-screensaver/shaders")) {
    if (key.endsWith(".frag.qsb")) {
      var slug = key.split("/").pop().replace(".frag.qsb", "");
      root.knownShaders[slug] = path
    }
  }
}
```

(Quickshell doesn't have direct file system access — this would need a `Process` or QML `FileIO` extension. Skip for MVP.)

---

## Phase 4: Tooling

### 4.1. Batch conversion script

Given a directory of shadertoy `.glsl` files, auto-port all:

```bash
#!/bin/bash
# convert-glsl.sh
# Usage: convert-glsl.sh <input-dir> <output-dir>

INPUT_DIR="$1"
OUTPUT_DIR="$2"
mkdir -p "$OUTPUT_DIR"

for f in "$INPUT_DIR"/*.glsl; do
  slug=$(basename "$f" .glsl)
  
  # Create vertex stage
  cat > "$OUTPUT_DIR/${slug}.vert" <<'VERTEX'
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;
void main() { qt_TexCoord0 = qt_TexCoord0; }
VERTEX

  # Copy frag (no edits) — user will need to review
  cp "$f" "$OUTPUT_DIR/${slug}.frag"

  # Bake both
  /usr/lib/qt6/bin/qsb --glsl "$OUTPUT_DIR/${slug}.frag" -o "$OUTPUT_DIR/${slug}.frag.qsb"
  /usr/lib/qt6/bin/qsb --glsl "$OUTPUT_DIR/${slug}.vert" -o "$OUTPUT_DIR/${slug}.vert.qsb"

  echo "Processed: $slug"
done
```

### 4.2. Shader gallery (QML)

A visual preview of available shaders (future enhancement):

- Grid of `ShaderEffect` previews, one per shader
- `time` advances per-preview independently (not synced)
- Click to preview, long-press to use
- `Image` fallback if shader fails to load

---

## Reference: Attribution

Every ported shader must preserve attribution. Add to `shaders/<slug>.md`:

```markdown
---
Source: https://www.shadertoy.com/view/<slug>
Author: <Name>
License: MIT / CC0 / ...
Original link: https://www.shadertoy.com/user/<author>
---
```

Keep attribution visible to the user via the IPC response:

```json
{
  "visible": true,
  "mode": "shader",
  "shader": "stardome",
  "source": "https://www.shadertoy.com/view/86Yg0E",
  "author": "Kali (MIT)"
}
```

---

## Files in this roadmap

| File | Purpose |
|---|---|
| `docs/roadmap.md` | This document |
| `moonshots/xscreensaver-hacks.md` | Xvfb offscreen stage (Phase 2+) — tracks the 270-hack moonshot |
| `shaders/` | Ported GLSL shaders + baked `.qsb` |
| `Service.qml` | `knownShaders` registry, `showShader()` |
| `bin/omarchy-overlay-screensaver` | CLI: `showShader <name>`, `list-shaders` |
