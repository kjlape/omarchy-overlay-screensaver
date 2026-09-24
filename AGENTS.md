# AGENTS.md

Guidance for AI coding agents (and humans in a hurry) working in this repo.

## What this repo is

A Quickshell **service plugin for omarchy-shell** (Omarchy 4+): it draws a
full-screen overlay above every window via a Wayland layer-shell surface on
`WlrLayer.Top`, controllable over IPC from ssh/another TTY. Two content
modes: a static image (defaults to the current omarchy background) or a
ported GLSL "shader hack" rendered by an in-process `ShaderEffect` — 8
ported so far, with ~24 more on the roadmap. Manual show/hide, no idle
trigger (deliberate — do not fight omarchy's built-in screensaver).

## Read before changing code

1. **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — the dev guide. How the
   plugin works, why it's built this way, gotchas, extension recipes, dev
   loop. Read this first.
2. **[docs/analysis.md](docs/analysis.md)** — pre-implementation research.
   Why layer-shell is the *only* mechanism that can overlay everything
   (no z-order in Hyprland window rules, fullscreen is workspace-local, no
   Wayland surface reparenting). Read before proposing "simpler" approaches.
3. **[docs/quickref.md](docs/quickref.md)** — one-page summary of the above.
4. **[docs/troubleshooting.md](docs/troubleshooting.md)** — read when the
   CLI says `IPC call failed` / `Target not found`: where the shell's logs
   really live, the FINAL-property gotcha, stale hot-reload compiles, and
   the diagnostic ladder.
5. **[docs/roadmap.md](docs/roadmap.md)** — the porting plan and, more
   importantly, the **operational knowledge for porting shaders**: the
   per-program checklist, the porting-tips list (coordinate-conversion
   families, idiom-golf unpacking, testing loop), and the status table
   that says which hack is next and what its difficulty class is.
   **Read the tips list before porting any shader.**

Task shortcuts: porting a shader → the project skill
[.agents/skills/port-shader/SKILL.md](.agents/skills/port-shader/SKILL.md)
(`/skill:port-shader`, or just "port next from roadmap") — a condensed,
verified loop; roadmap.md (checklist + tips) and the "Porting a shader
hack" section below are the authority when anything is unclear. Anything
involving blank overlays / dead IPC / weird reload behavior →
troubleshooting.md's diagnostic ladder. Changing QML structure →
ARCHITECTURE.md first.

## Key files

| File | Role |
|---|---|
| `Service.qml` | The whole plugin: overlay surfaces (`Variants` → `PanelWindow` per monitor), config lookup, shader content mode, `IpcHandler` (`show`/`shader`/`hide`/`toggle`/`status`/`kill`). Read it in full. |
| `shaders/` | Ported GLSL hacks (8: starnest, universeball, topologica, synthwavecity, downfall, trizm, hexplasma, stardome) — Vulkan-style GLSL sources + baked `.qsb` per stage. `universeball.frag` and `topologica.frag` headers are the canonical coordinate-conversion references. |
| `manifest.json` | Plugin identity `kjlape.overlay-screensaver`, service-only, `keepLoaded: true`. Schema is Omarchy's; validate with `omarchy plugin validate .` |
| `bin/omarchy-overlay-screensaver` | CLI wrapper. Its real job is rebuilding `XDG_RUNTIME_DIR`/`OMARCHY_PATH` so the IPC call works from non-interactive ssh. |
| `install.sh` / `uninstall.sh` | CLI-on-PATH only. The plugin itself is installed via `omarchy plugin add <repo> --enable` — these scripts never touch `~/.config/omarchy/`. |
| `vendor/xscreensaver/` | Reference copies from the xscreensaver 6.16 release, **not built/shipped**: `hacks/glx/glsl/` (38 `.glsl` files — porting sources, each keeping its author/license header) and `hacks/xmatrix.c` / `hacks/glx/glmatrix.c` + `hacks/images/matrix*.png` (the Matrix hacks, vendored for `moonshots/matrix-hacks.md`). License matrix (which files are safe to port vs do-not-ship) is in `vendor/xscreensaver/README.md`. |
| `moonshots/` | Design sketches for half-baked extension ideas (not implemented, not committed to). See its README. Currently: [xscreensaver-hacks.md](moonshots/xscreensaver-hacks.md) — running the full xscreensaver hack collection via an offscreen Xvfb + frame-capture stage. Verified licensing/portability facts live there. |
| `README.md` | User-facing: install, usage, the dismissal/recovery ladder. |

## Rules for changes

- **The recovery guarantee is load-bearing**: the overlay must always start
  with `visible: false`, with no persisted visibility state. `kill`
  (shell restart) is the documented break-glass recovery; anything that lets
  the overlay come back up after a restart breaks the failsafe.
- The `WlrLayershell.namespace` (`omarchy-overlay-screensaver`) must stay
  unique — don't rename it casually.
- `WlrKeyboardFocus.Exclusive` may only be set on the visible overlay
  surface, never on an always-mapped one.
- `omarchy-shell` IPC can exit 0 on failure — callers must check the result
  string, not the exit code.
- shell.json `plugins[]` config is read through `pluginConfig`; new options go
  through `cfg(name, fallback)` with safe defaults.
- Copy patterns from installed reference plugins rather than inventing:
  `~/.config/omarchy/plugins/nosignal.motion-wallpaper/` (per-monitor panels,
  state-file guards), `/usr/share/omarchy/shell/plugins/clipboard/`
  (exclusive keyboard focus + Escape key catcher),
  `~/dev/kjlape/omarchy-remote-lock/` (ssh-safe IPC CLI, injected shell
  properties).

## Dev loop

```bash
omarchy plugin validate .                 # manifest check — run after every manifest edit
# dev-install as a symlink (survives edits, hot-reloads):
ln -sfn "$PWD" ~/.config/omarchy/plugins/kjlape.overlay-screensaver
omarchy plugin enable kjlape.overlay-screensaver
omarchy-shell shell rescanPlugins         # force-reload — often INSUFFICIENT, see below
omarchy restart shell                     # the reliable reload; always safe (overlay starts hidden)
```

QML edits hot-reload on save when installed under `~/.config/omarchy/plugins/`
… but **not reliably**: a registry edit can sit unseen (old `knownShaders`
still served) even after `omarchy-shell shell rescanPlugins`. When the
shell's behavior doesn't match the file on disk (verify with `sed -n '<line>p'
<file>` against what you're seeing), don't debug the code — follow
troubleshooting.md's ladder: scratch `quickshell -n -p /tmp/qstest` loads
the file in isolation (proves the code is fine), then `omarchy restart
shell` (always safe — the overlay starts hidden). Treat a restart as part
of any registry/shader change; it costs seconds and removes the stale-cache
variable entirely.

Test recovery paths explicitly before committing: `hide`, `kill`, Escape,
click. Plugin `console.log` output lands in the shell's journal
(`journalctl --user -u "wayland-wm@hyprland.desktop.service"` — not
`-u omarchy-shell`, which doesn't exist on Omarchy 4; see
docs/troubleshooting.md). GL link/compile errors land there too — a blank
overlay usually means a silent link failure; grep the journal for the
timestamp window of the show before suspecting the port.

## Porting a shader hack (the most common iteration)

The full procedure, difficulty classes, and hard-won tips are in
[docs/roadmap.md](docs/roadmap.md) — the tips list is **required reading**
before a first port (coordinate-conversion families, `iMouse` re-basing,
idiom-golf unpacking). The condensed loop, verified working:

1. Pick the next program from the roadmap Phase 1 status table (license-
   blocked rows are marked — do not ship them).
2. Copy `vendor/xscreensaver/hacks/glx/glsl/<name>.glsl` →
   `shaders/<name>.frag`; keep the upstream header verbatim, adaptation
   notes after it. Port: `mainImage` → `main`, input → `qt_TexCoord0`
   (location 0, that exact name), `iTime` → `time`, `iResolution` →
   `aspect` (w/h) — **audit every `iResolution` reference first; the last
   one may be dead code you can simply delete** (stardome's `aa`). Copy the
   coordinate-conversion block from `universeball.frag`
   (`res.y`-normalized family) or `topologica.frag` (plain `[-1,1]`
   family) per tip 9 — read upstream's `fragCoord → uv` line to pick.
   Flip y either way (Qt texcoords run top-down).
3. Copy any existing `shaders/<name>.vert` (passthrough; NVIDIA linker
   requires the explicit-location output — never rely on Qt's default).
4. Bake **immediately** (`qsb` catches typos in seconds):
   `/usr/lib/qt6/bin/qsb --glsl "100,120,150,330,440" shaders/<name>.frag -o shaders/<name>.frag.qsb` (same for `.vert`).
   Commit the `.qsb` files — `qsb` isn't guaranteed on install machines.
5. Add one line to `knownShaders` in `Service.qml` — that's the only QML
   change a port needs.
6. `omarchy restart shell`, then smoke-test with no visuals:
   `omarchy-overlay-screensaver shaders` (lists the registry) and `status`
   (JSON keeps `mode`/`shader` after hide).
7. Visual test without leaving the screen covered:
   `( sleep 10; omarchy-overlay-screensaver hide ) & omarchy-overlay-screensaver shader <name>` —
   and verify with a `grim` capture mid-window (view it directly, or
   ImageMagick region means for orientation: horizon/ground should be at
   the bottom). Skew/stretch = conversion math (tip 7), not the algorithm.
8. Journal check for GL errors, docs update (roadmap row + status count,
   README port list), commit.

State flags must never shadow final QML properties (`visible`, `anchors`,
…); the overlay's flag is `overlayVisible` for that reason — renaming it
back breaks the whole component load.

Do not edit anything under `/usr/share/omarchy/` — read it freely, never
write it. User config lives in `~/.config/omarchy/`.