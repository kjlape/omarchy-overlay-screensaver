---
name: port-shader
description: >
  Port the next GLSL shader hack in this repo's roadmap (docs/roadmap.md).
  Use when asked to "port next from roadmap", "port the next shader hack",
  or to port a named shader from vendor/xscreensaver/hacks/glx/glsl/ into
  shaders/ and register it. Covers the full verified loop: port, bake,
  register, restart, test, document, commit. Project-local to
  omarchy-overlay-screensaver.
---

# Port a shader hack (omarchy-overlay-screensaver)

Run everything from this repo's root. The plugin is dev-installed as a
symlink from `~/.config/omarchy/plugins/kjlape.overlay-screensaver` — QML
changes apply without reinstall.

Deep knowledge lives in the repo docs — read if anything below is unclear:
`docs/roadmap.md` (status table, per-program checklist, porting tips 1–16),
`AGENTS.md` (rules), `docs/troubleshooting.md` (diagnostic ladder).

## Pick the target

Open `docs/roadmap.md`, Phase 1 table. Take the next row **not** marked
✅ Done, in priority order (🔴 before 🟡 before 🟢), skipping any row whose
license is unverified/marked do-not-ship (the table says which). If the user
named a shader, use that one.

## Port (steps 2–3 of the checklist; tips list is the reference)

1. Read `vendor/xscreensaver/hacks/glx/glsl/<name>.glsl` **in full**.
   Grep it for `iTime|iResolution|iMouse|iFrame|iChannel|RESOLUTION` —
   every hit needs a plan.
2. Write `shaders/<name>.frag`:
   - Upstream header **verbatim**; adaptation-notes comment block after it.
   - `#version 440`; `layout(location = 0) in vec2 qt_TexCoord0;` (that
     exact name); `layout(location = 0) out vec4 fragColor;`.
   - Uniform block (copy from any existing port):
     `mat4 qt_Matrix; float qt_Opacity; float time; float aspect;`
   - `iTime` → `time`; `iResolution` → `aspect`. **Audit every
     `iResolution`/`RESOLUTION` hit — the last one may be dead code you can
     delete** (stardome's `aa`); only a live pixel-size term would force a
     new uniform (none have yet).
   - `mainImage(out vec4, fragCoord)` → `main()`. Coordinate conversion:
     read upstream's `fragCoord → uv` line to pick the family, then copy the
     block verbatim from the reference frag —
     - `u = (2*fragCoord - res)/res.y` family → `shaders/universeball.frag`:
       `u = (qt_TexCoord0*2 - 1) * vec2(aspect, 1)`. NEVER
       `(2*uv - vec2(aspect,1))` — that skews/stretches x.
     - plain `uv = fragCoord/res*2 - 1` family → `shaders/topologica.frag`:
       `u = qt_TexCoord0*2 - 1`, no scaling in the map; apply `p.x *= aspect`
       wherever upstream applies `res.x/res.y`.
     - Either way **flip y** (`u.y = -u.y`) — Qt texcoords run top-down.
   - `iMouse` → drop, keeping the time-driven term (e.g.
     `iMouse.x/res.x*2π + iTime*0.01` → `time*0.01`); mark substitutions
     `// jwz: was … — mouse dropped`.
   - Unpack idiom-golf carefully: initialize loop outputs before the loop,
     `0.`-suffix rewritten literals, re-base `iFrame` tricks on `time`.
3. Write `shaders/<name>.vert` — byte-identical copy of
   `shaders/stardome.vert` except the first comment line names `<name>`.

## Bake, register, reload

```bash
/usr/lib/qt6/bin/qsb --glsl "100,120,150,330,440" shaders/<name>.frag -o shaders/<name>.frag.qsb
/usr/lib/qt6/bin/qsb --glsl "100,120,150,330,440" shaders/<name>.vert -o shaders/<name>.vert.qsb
```
(qsb catches typos in seconds — bake immediately after writing.)
Commit the `.qsb` files; `qsb` isn't guaranteed on install machines.

Then the **only** Service.qml change — one line in `knownShaders`:
`"<name>": "shaders/<name>.frag.qsb",` (append, keep the map valid).

Reload: `omarchy restart shell` (rescanPlugins is often insufficient —
stale compiles are a documented gotcha; the restart is always safe because
the overlay starts hidden).

## Test

1. Smoke (no visuals): `omarchy-overlay-screensaver shaders` lists `<name>`;
   `omarchy-overlay-screensaver status` returns JSON.
2. Visual, never leaving the screen covered:
   ```bash
   ( sleep 10; omarchy-overlay-screensaver hide ) & omarchy-overlay-screensaver shader <name>
   ```
   Capture mid-window (`grim /tmp/<name>.png`) and inspect: orientation
   (horizon/ground at bottom = y-flip right), no skew/stretch (skew =
   conversion math, tip 7 — not the algorithm). Mind upstream fade cycles:
   a `mod(iTime)` loop with fade gates is black at cycle edges.
3. Journal check for GL link/compile errors:
   `journalctl --user -u "wayland-wm@hyprland.desktop.service" --since "-2 min"`
   (grep the window of the show; xkbcomp noise is irrelevant).

## Document + commit

- `docs/roadmap.md`: table row → `✅ Done — <port notes>`; Status line count
  N/32 + name appended; add a porting tip if you learned something new.
- `README.md`: append a bullet to the "Current ports" list.
- Commit style: `feat(shader): port <name> (<author>, <license>)` with a
  body covering the port class and any new tips. Keep the upstream license
  header verbatim in the `.frag` — that's the attribution record.

## Hard rules (from AGENTS.md)

- Overlay always starts `visible: false`; nothing persists visibility.
- New ports must not need Service.qml changes beyond the registry entry.
- If the registry change doesn't show up in `shaders` after restart:
  verify the file on disk, run the scratch-instance check from
  troubleshooting.md before suspecting your code.
