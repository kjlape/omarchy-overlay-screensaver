# Roadmap: Xscreensaver Port

## Overview

Goal: expand the `kjlape.overlay-screensaver` from a single ported GLSL hack (`starnest`) to a library of **portable, per-frame fragment shaders** that run in-process inside the `ShaderEffect` overlay surface.

This is the **complement path** from `moonshots/xscreensaver-hacks.md`: no Xvfb, no child-process tree, no Wayland gaps — everything is a QML `ShaderEffect` bound to the existing `PanelWindow`/`WlrLayer.Top` surface.

The "run all 270 hacks" moonshot via Xvfb is tracked separately under `moonshots/xscreensaver-hacks.md`. This document is strictly for the **shader-based subset** (~20–50 programs) that ports directly to Qt 6 `ShaderEffect`.

## Status

- [x] Phase 0: porting recipe established (`starnest`)
- [~] Phase 1: xscreensaver `glx/glsl/` collection (32 programs, 38 files — verified against local 6.16 tree). In progress: 8/32 ported (`starnest`, `universeball`, `topologica`, `synthwavecity`, `downfall`, `trizm`, `hexplasma`, `stardome`). The `universeball` port also landed the multi-shader API — `showShader(name, source)`, `shader [NAME]` / `shaders` CLI verbs — so future ports need no Service.qml changes beyond a `knownShaders` entry.
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
5. Test: `omarchy-overlay-screensaver shader <name>`

**Gotchas** (documented in ARCHITECTURE.md):
- NVIDIA linker requires explicit-location vertex output
- QSL hot-reload may serve stale compiles — use `omarchy-shell shell rescanPlugins`
- `starnest` used `iMouse` (dropped for screensaver use); replace with `time`-driven animation

---

## Phase 1: xscreensaver `glx/glsl/` Collection (32 programs)

These are vendored in-repo at `vendor/xscreensaver/hacks/glx/glsl/` (copied from the xscreensaver 6.16 tree — 38 `.glsl` files: some hacks are multi-pass; provenance and license matrix in `vendor/xscreensaver/README.md`). They are the **safest** starting point — already vetted and, in most cases, explicitly licensed by the upstream shadertoy authors.

### Target programs

All files are single-pass `mainImage` shaders unless noted. Verified from the local tree:

| # | File(s) | Program | Author (license) | Notes | Priority |
|---|---|---|---|---|---|
| 1 | `starnest.glsl` | Star Nest | Kali (MIT) | ✅ Done | ✅ |
| 2 | `topologica.glsl` | Topologica | otaviogood (CC0) | ✅ Done — `iMouse` dropped; camera drifts on `time` alone; anti-unroll trick re-based on `time` | ✅ |
| 3 | `stardome.glsl` | Stardome | mrange (CC0) | ✅ Done — 300 lines but near-copy-paste: no `iMouse`/textures; the only non-`main` `iResolution` use is an unread local (`aa` in `grid()`) so the port needs no resolution uniform; upstream's 30 s `mod(iTime)` camera loop with fade-in/out gates kept verbatim (breathing pulse is upstream intent) | ✅ Done |
| 4 | `universeball.glsl` | Universe Ball | Matt Vianueva (MIT, relicensed) | 43 lines, trivial port | ✅ Done |
| 5 | `bubblecolors.glsl` | Bubble Colors | Matt Vianueva (license **unverified** — no statement in file) | 23 lines | 🔴 High |
| 6 | `downfall.glsl` | Downfall | Matt Vianueva (MIT, relicensed) | 35 lines | ✅ Done |
| 7 | `trizm.glsl` | Trizm | Matt Vianueva (MIT, relicensed) | ✅ Done — 64 lines; per-pixel start-distance dither re-based on converted uv (no pixel-resolution uniform); `o *= i` golf dropped | ✅ Done |
| 8 | `hexplasma.glsl` | Hex Plasma | Nemerix (MIT) | 57 lines | ✅ Done — cleanest port yet: no `iMouse`, no textures, `res.y`-normalized coordinate family (universeball conversion block verbatim); only edits were the uniform block, `iTime` → `time`, and the y flip |
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
| 21 | `synthwavecity.glsl` | Synthwave City | 3w36zj6 (derivative; original **CC BY 3.0**) | attribution required — deprioritize for license reasons | ✅ Done |
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

### Verified-facts summary (2026 check against 6.16 tree, now vendored)

- **Count**: 38 `.glsl` files / 32 distinct programs under `hacks/glx/glsl/`.
- **Multi-pass** (filename pattern `<pass>` or `N-M.glsl`): `bestill` (6 passes), `neongravity` (2 passes). Everything else is single-pass.
- **Texture users** (need QML `source` images or rework): `gimbalharmonics`, `neongravity` (pass 0), `protophore`, `skyline`.
- **`iMouse` users** (replace with time-driven values): `alienbeacon`, `elementalring`, `fluxcore`, `gimbalharmonics`, `prococean`, `protophore`, `skyline`, `starnest` (already handled), `topologica`.
- **License-block absent / ambiguous**: `bubblecolors`, `driftclouds` (no license statement — verify with author or upstream xscreensaver before shipping), `amigajuggler` (xscreensaver-in-house, effectively GPL), `synthwavecity` (derivative of a CC BY 3.0 original — attribution obligation).
- **Everything else** carries an explicit CC0/MIT header (several Matt Vianueva shaders were explicitly relicensed to MIT by the author for xscreensaver inclusion).

### Per-program task checklist

For each of the remaining 31 programs (vendored at
`vendor/xscreensaver/hacks/glx/glsl/<name>.glsl`):

```
[ ] 1. Copy the GLSL source from the vendored xscreensaver 6.16 tree
[ ] 2. Create shaders/<name>.vert (qt_TexCoord0 passthrough — copy
       shaders/starnest.vert, keep a per-shader copy: the ShaderEffect
       swaps stages by URL and the recipe stays uniform per port)
[ ] 3. Port shaders/<name>.frag:
       - Rename iTime → time
       - Rename iResolution → aspect — CAREFUL: shadertoy's
             (2*fragCoord - res)/res.y with fragCoord = uv*(aspect,1) becomes
             u = (2*uv - 1)*vec2(aspect,1), NOT (2*uv - vec2(aspect,1));
             also flip y (Qt texcoords run top-down, shadertoy bottom-up).
             (Wrong version = skewed, x-stretched image — universeball bug)
       - Input: qt_TexCoord0
       - Output: fragColor
       - Drop iMouse dependency (replace with time-driven values)
       - Ensure uniform block is correct
       - Multi-pass files (bestill N-M, neongravity N): chain ShaderEffects
             with a texture between passes, or merge into one pass if feasible
       - Texture-channel users: supply textures via QML source properties
             or strip the texture dependency
[ ] 4. Bake: qsb --glsl "100,120,150,330,440" shaders/<name>.frag -o shaders/<name>.frag.qsb
[ ] 5. Bake: qsb --glsl "100,120,150,330,440" shaders/<name>.vert -o shaders/<name>.vert.qsb
[ ] 6. Add to knownShaders in Service.qml:
       readonly property var knownShaders: ({ ..., "<name>": "shaders/<name>.frag.qsb" })
       (that's the ONLY Service.qml change — the ShaderEffect resolves stages
       dynamically from shaderName via activeFragUrl/activeVertUrl)
[ ] 7. Test: omarchy-overlay-screensaver shader <name>
       (IPC form: omarchy-shell overlayscreensaver showShader <name> <source>)
       and verify `omarchy-overlay-screensaver shaders` lists it
[ ] 8. Preserve the upstream license header verbatim in the .frag file
```

`universeball` was the first port done under this multi-shader API and
doubles as the reference for the 1→N step: `showShader` takes the shader
name as its first argument (empty = configured default), the CLI grew
`shader [NAME]` and `shaders`, and `status` now reports the full registry.

### Porting tips (learned porting `starnest`, `universeball`, `topologica`)

Hard-won, in rough order of when they bite:

1. **Do the coordinate conversion once, correctly.** Shadertoy
   `u = (2*fragCoord − res)/res.y` with `fragCoord = uv·(aspect,1)`
   simplifies to `u = (2*uv − 1)·vec2(aspect, 1)` — do NOT translate by
   `vec2(aspect,1)`, that skews + stretches x (the universeball bug).
   Flip y too: Qt texcoords run top-down, shadertoy bottom-up.
   Copy the conversion block verbatim from `shaders/universeball.frag` —
   it carries this gotcha in its header comment as a permanent warning.
2. **Unpack the idiom-golf carefully.** Upstream shaders are compressed
   for brevity: undefined-until-written outputs (shadertoy guarantees the
   first write happens; Qt/GLSL does not — initialize `c`/`o` before the
   loop, see the `// jwz` init lines), comma-operator chains in `for`
   headers, and float literals that must be re-`0.`-suffixed when
   rewritten. Expanding them into readable statements makes the diff
   against upstream reviewable.
3. **Keep the upstream header verbatim, adaptation notes after it.**
   License/attribution block untouched; a comment block below records what
   was adapted (inputs, uniforms, dropped `iMouse`) — that's provenance
   for every future reader.
4. **Bake + restart, don't trust hot-reload.** `.qsb` changes don't
   trigger a QML reload and reloads can serve stale compiles
   (ARCHITECTURE.md “Shader content”): `qsb` both stages, then
   `omarchy restart shell` before judging a port.
5. **Test with a scheduled auto-hide** so the screen is never left
   covered while you eyeball a new port:
   `( sleep 6; omarchy-overlay-screensaver hide ) & omarchy-overlay-screensaver shader <name>`
6. **Check the journal, not just your eyes**: GL link/compile errors land in
   `journalctl --user -u "wayland-wm@hyprland.desktop.service"` (grep the
   timestamp window of the show; see troubleshooting.md). A blank/black
   overlay usually means a silent link failure.
7. **A skewed or stretched image means conversion math, not the port.**
   Verify against the shadertoy preview at the same aspect before
   suspecting the algorithm port.
8. **CLI edits need `install.sh`** — the PATH copy at `~/.local/bin` is a
   copy, not a symlink; plugin QML is hot-reloaded (symlinked install),
   the CLI is not.
9. **Check which coordinate mapping upstream uses before copying the
   conversion block.** The universeball gotcha (tip 1) applies to the
   `res.y`-normalized family, `u = (2·fragCoord − res)/res.y`. Topologica
   instead maps `uv = fragCoord/res·2 − 1` (a plain `[−1,1]` square) and
   handles aspect inside the camera basis (`uv.x · sideNorm · aspect`) —
   for that family the correct port is `u = 2·qt_TexCoord0 − 1` plus the
   y flip, no `vec2(aspect,1)` scaling at all. Some members of that
   family then apply the ratio explicitly after the map (`stardome`:
   `p.x *= res.x/res.y`) — keep that: map plain, y flip, then scale at
   the exact point upstream did. Read the upstream `fragCoord → uv`
   line first; picking the wrong family produces the same
   skew symptoms as tip 7.
10. **Re-base upstream runtime-state tricks on uniforms you actually
   have.** Shadertoy-only inputs (`iFrame`, `iMouse`, `iChannel*`) appear
   in non-obvious places — topologica's anti-unroll `ZERO_TRICK` was
   `max(0, -iFrame)`, re-based on the `time` uniform as
   `max(0, -int(time))` (note the explicit `int()` cast; the float isn't
   implicit in GLSL 440). Grep the source for every `i*` uniform before
   porting, not just the obvious `iMouse` in the camera block.
11. **When dropping `iMouse`, keep the time-driven terms, don't zero the
   whole angle.** `mx = iMouse.x/res.x·2π + iTime·0.01` becomes just
   `time · 0.01` — the camera still drifts/orbits naturally instead of
   freezing. Mark each substitution inline with the `// jwz: was … —
   mouse dropped` convention so the diff against upstream stays
   reviewable (see `shaders/topologica.frag` for the pattern).
12. **Ports with no `iMouse`/textures/multi-pass are near-copy-paste.**
   `hexplasma` (the 7th port) needed only: paste the body, replace
   `mainImage` with `main`, swap in the standard uniform block, apply the
   universeball conversion block (it's the `res.y`-normalized family),
   rename `iTime` → `time`, and bake. Budget ~10 minutes for this class;
   GLSL 440 built-ins the sources use (`tanh`, `smoothstep`, `mat2`) all
   work unmodified under `qsb`. Check a source against the roadmap table's
   Notes column first to know which class you're in.
13. **Bake immediately after writing the GLSL.** `qsb` catches syntax
    typos (a stray `1.0_`) in seconds — far cheaper than discovering them
    after a shell restart + auto-hide test cycle. Treat
    `qsb && qsb` as part of writing the file, not a separate step
    (per-program checklist steps 4–5).
14. **`status` is a no-visual smoke test.** After the first show, the
    JSON keeps `mode`/`shader` even once hidden — use it to confirm the
    registry entry and name resolution (`shaders` verb + `status`) before
    spending a show cycle on a possibly-broken port.
15. **Audit every `iResolution`/`RESOLUTION` reference — the last one may
    be dead code.** Tip 10 says grep for all `i*` uniforms; for
    `iResolution` specifically, check each hit is actually read. Stardome
    only referenced `RESOLUTION.y` outside `main()` as an *unread* local
    (`float aa = 2.0/RESOLUTION.y;` in `grid()`) — deleting it left zero
    resolution dependency, so the port ships with the standard
    `time`/`aspect` uniform block and no plumbing changes. If a live
    pixel-size term (`aa = 2.0/res.y` used for AA widths) survives the
    audit, that's when a resolution uniform becomes unavoidable.
16. **Verify visually with a screenshot, not just live eyes.** You can
    inspect the overlay without watching it: while the auto-hide window
    (tip 5) runs, `grim -o <output> /tmp/<name>.png` captures the overlay
    mid-animation; the image can be viewed directly, or region-analysed
    with ImageMagick (`-crop x360+0+0` strips + `-format
    "%[fx:mean]"` per screen third) to confirm orientation and brightness
    structure without eyeballing anything live. Stardome's port was
    verified this way: horizon glow in the bottom third, sparse stars
    up top, clean (unskewed) grid curves — the tip-7 failure classes are
    all visible in the capture.
    (Bake fades into account: a shader with an upstream `mod(iTime)`
    loop + fade gates — stardome — is black at cycle edges; capture
    mid-cycle.)

Cross-references: the bake/reload/hot-reload mechanics are documented in
[ARCHITECTURE.md](ARCHITECTURE.md) “Shader content”; the diagnostic ladder
for blank overlays in [troubleshooting.md](troubleshooting.md); the
per-program checklist above; `shaders/universeball.frag`'s header is
the canonical copy-paste source for the conversion block (tip 1's
`res.y`-normalized family — see tip 9 for the other family); and
`shaders/topologica.frag` is the reference for the plain `[−1,1]`
mapping, `iMouse`-drop substitutions, and the `ZERO_TRICK` re-base, and
`shaders/stardome.frag` is the same family with the explicit post-map
`p.x *= aspect` (tip 9's sub-variant).

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

**Vertex stage template** (the `shaders/starnest.vert` shape — ShaderEffect
declares `position` (loc 0) and `texCoord` (loc 1) as inputs; the earlier
"4-line passthrough" sketch in this section does not compile):
```glsl
#version 440
layout(location = 0) in vec4 position;
layout(location = 1) in vec2 texCoord;
layout(location = 0) out vec2 qt_TexCoord0;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float aspect;
};

void main() {
    qt_TexCoord0 = texCoord;
    gl_Position = qt_Matrix * position;
}
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
[ ] 6. Bake both: qsb --glsl "100,120,150,330,440" shaders/<slug>.frag -o shaders/<slug>.frag.qsb
[ ] 7. Register in Service.qml knownShaders (only change needed)
[ ] 8. Test: omarchy-overlay-screensaver shader <slug>
```

---

## Phase 3: Config + UX Integration

Once you have a library of shaders, wire them up:

### 3.1. `shell.json` config

Current config already supports `shader: "starnest"`. This should work for any ported name:

```json
{
  "id": "kjlape.overlay-screensaver",
  "image": "",
  "shader": "stardome"
}
```

(Keys sit directly on the `plugins[]` entry — that's how `cfg()` reads
them; verified against Service.qml during the 1→N step.) This sets the
DEFAULT shader for the `shader` CLI verb / `showShader` with an empty name;
explicit `shader <name>` always wins.

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

### 3.3. List of available shaders — DONE (1→N step)

Landed with `universeball`: `shaders()` on the `IpcHandler` returns the
registry names newline-joined, the CLI exposes it as
`omarchy-overlay-screensaver shaders`, and `status()` reports the full
list in its `shaders` field. If a prettier payload (labels, credits) is
needed later, pair it with 3.2's registry file.

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
