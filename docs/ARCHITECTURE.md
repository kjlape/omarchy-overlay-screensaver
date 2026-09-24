# Architecture — kjlape.overlay-screensaver

A dev-facing guide to how this plugin works, why it is built this way, and how
to extend it. User-facing usage lives in the top-level [README](../README.md).

## Big picture

Omarchy's bar, notifications, OSD, and all plugins run inside a single
long-lived Quickshell process (`omarchy-shell`). This plugin contributes one
service to that process: a set of full-screen layer-shell surfaces plus an IPC
handler.

```
┌──────────────────────────────────────────────────────────────┐
│ omarchy-shell (Quickshell process)                            │
│                                                              │
│  Service.qml  (the plugin's service instance)               │
│  ├── property bool visible      ── the one bit of state      │
│  ├── IpcHandler target "overlayscreensaver"                   │
│  ├── Variants { model: Quickshell.screens }                  │
│  │     └── PanelWindow per monitor  ← the overlay surfaces    │
│  └── Process: readlink current background (image fallback)    │
└──────────────────────────────────────────────────────────────┘
        ▲                                   │
        │ IPC socket                        │ Wayland layer-shell
        │                                   ▼
  bin/omarchy-overlay-screensaver   Hyprland composites each surface
  (works from ssh / TTY)            on WlrLayer.Top, above all toplevels
```

### Why layer-shell (and not a fullscreen window)

The pre-implementation research in [analysis.md](analysis.md) documents the
dead ends; the short version:

- Hyprland window rules have **no z-order field** — a regular toplevel can
  never be forced above other toplevels.
- Client fullscreen is **workspace-local** — it vanishes on workspace switch.
- Wayland forbids cross-client surface reparenting.

The only surfaces a compositor places above/below all toplevels are
**layer-shell** surfaces. `WlrLayer.Top` sits above the layer that contains
the bar and above all toplevels, on every workspace. This is the intended
mechanism, not a hack. Reference implementations: `omarchy.background`
(`WlrLayer.Background`), `nosignal.motion-wallpaper` (also Background), and
the built-in clipboard/emoji panels (Top/Overlay with exclusive keyboard
focus).

### Wayland layer stack (bottom → top)

```
WlrLayer.Background   ← omarchy.background, nosignal.motion-wallpaper
WlrLayer.Bottom
WlrLayer.TopLevel     ← all regular windows, including fullscreen ones
WlrLayer.Overlay
WlrLayer.Top          ← omarchy bar, and THIS PLUGIN's overlay
```

## Anatomy of Service.qml

### Injected properties

The omarchy shell injects four properties into every service instance
(from its `shell.qml` `_syncServices`/`ensureService`): `shell`,
`pluginRegistry`, `manifest`, `omarchyPath`. They are declared as loose
`property var` on the root `Item` and must not be removed.

### Config from shell.json

`pluginConfig` digs this plugin's entry out of the live
`~/.config/omarchy/shell.json` `plugins[]` array (matching by `id`, tolerating
the `@` prefix omarchy uses for some references). Currently two keys:

- `image` — absolute path to the overlay image. Falls back to the
  current background via `readlink -f ~/.local/state/omarchy/current/background`
  (the same symlink `omarchy.background` follows).
- `shader` — name of the GLSL hack used as the **default** by
  `showShader`/the `shader` CLI verb when no name argument is passed
  (default `starnest`). An explicit name argument always wins; unknown
  names are rejected (error string, nothing shown).

shell.json hot-reloads on save, but `pluginConfig` is a binding over
`shell.shellConfig`, so config edits land live without a plugin rescan.

### State model — deliberately minimal

One bit that matters: `overlayVisible: false`. (The content-mode selection
`image`/`shader` is also state, but it is deliberately outside the visibility
path — the overlay still always initializes hidden and image-mode, so a
shell restart remains a guaranteed recovery even mid-shader.) No state file,
no daemon, nothing that survives a restart. If you add state, keep it out of
the visibility path.

### The overlay surfaces

`Variants { model: Quickshell.screens }` instantiates one `PanelWindow` per
monitor, so multi-head is covered and hotplugged screens are handled on the
next shell reload. Each surface:

- `anchors { top; bottom; left; right }` — full screen
- `WlrLayershell.namespace: "omarchy-overlay-screensaver"` — must stay unique
  (see "gotchas" below)
- `WlrLayershell.layer: WlrLayer.Top`
- `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive` — grabs the
  keyboard **while the surface exists**. The surface only exists while
  `visible`, so nothing is grabbed the rest of the time. Exclusive focus is
  what makes Escape reliable and also what blocks all other input — intended
  for a screensaver, but the reason the IPC/kill ladder exists.
- `exclusionMode: ExclusionMode.Ignore` — the surface must not reserve
  space in the layout or affect struts.

Input handling inside each surface:

- A `MouseArea` over the whole overlay → click to dismiss.
- An `Item { focus: true }` with `Keys.onPressed` → **any keystroke** to dismiss.
  This is the same key-catcher pattern the built-in clipboard panel uses
  (which handles `Keys.onEscapePressed`; the generic `onPressed` signal here
  catches every key).


The image is `Image.PreserveAspectCrop`, `asynchronous: true`, sourced from
`file://<path>`. Empty path → black (the PanelWindow `color`).

### Shader content (ported GLSL hacks)

`contentMode === "shader"` swaps the `Image` for a `ShaderEffect` inside the
same surface, rendering a ported xscreensaver/shadertoy fragment shader —
see `moonshots/xscreensaver-hacks.md` for why this is the sane subset of the
"run all hacks" moonshot (they're per-frame fragment shaders; no Xvfb
pipeline needed). Everything runs in-process on the GPU, so the recovery
guarantee and the whole dismissal ladder are untouched.

Moving parts, all of which cost debugging time — copy this recipe:

- **Shaders live in `shaders/`** as Vulkan-style GLSL sources, baked to
  `.qsb` by qt6-shadertools. Rebuild after editing:
  `/usr/lib/qt6/bin/qsb --glsl "100,120,150,330,440" shaders/<name>.frag -o shaders/<name>.frag.qsb`
  (baked `.qsb` files are committed — `qsb` isn't guaranteed on install
  machines). A QML-source `fragmentShader:` needs the built file, not the
  raw GLSL.
- **The registry is `knownShaders` in Service.qml** — name → frag `.qsb`
  path. Adding a port is: `shaders/<name>.vert`, ported `<name>.frag`,
  bake both, add the map entry. `resolveShaderName()` maps a request (or,
  if empty, the configured default) to a registry key; the `ShaderEffect`
  binds `activeFragUrl`/`activeVertUrl`, derived from `shaderName`, so the
  shader swaps by changing that one property. All vertex stages are the
  same passthrough (`shaders/starnest.vert` shape) but each shader ships
  its own copy anyway — Qt reloads both stages when either URL changes,
  and per-shader files keep the port recipe uniform.
- **The fragment input MUST be named `qt_TexCoord0`** (location 0) — anything
  else fails to match Qt's vertex stage with a confusing link error.
- **Ship your own vertex stage too** (`starnest.vert`): Qt's implicit default
  has no explicit-location output, and the NVIDIA linker refuses to match it
  against the fragment input (`Failed to link shader program: … no matching
  output`). Costless to include; saves the mystery.
- **Uniforms by name**: `property real time` on the ShaderEffect maps to the
  `time` float in the shader's uniform block (after `qt_Matrix`/`qt_Opacity`).
  `aspect` (w/h) is passed instead of `iResolution`.
- **Animation clock**: a plain 16 ms `Timer` increments `root.shaderTime`
  while `overlayVisible && contentMode === "shader"`. This Quickshell build
  has no `FrameTimer`.
- Hot-reload gotcha: **`.qsb` changes do not trigger a QML reload, and QML
  reloads can serve stale compiles** — after shader edits, `omarchy restart
  shell` is the reliable test. Iterate in a scratch instance first (see
  troubleshooting.md).
- **Porting tips** — the shadertoy→Qt coordinate conversion (with the
  skew bug it caused), idiom-golf unpacking, provenance comment
  conventions, and the bake/restart/test-with-auto-hide loop are
  collected in [roadmap.md](roadmap.md) “Porting tips”; the reference
  port with the canonical conversion block is `shaders/universeball.frag`.
- Multi-monitor: each surface gets its own `ShaderEffect` instance; they all
  bind the same `root.shaderTime`, so the animation is in sync.

### IPC

`IpcHandler { target: "overlayscreensaver" }` exposes:

| Method | Args | Notes |
|---|---|---|
| `show(source)` | source tag for logging | returns `"ok"`; image mode |
| `showShader(shader, source)` | name (empty = configured default) | shader mode (`shader [NAME]` CLI verb); unknown name → error string, nothing shown |
| `shaders()` | | newline-joined registry names (`shaders` CLI verb) |
| `hide(source)` | | |
| `toggle(source)` | | |
| `status()` | | JSON: `{visible, mode, shader, shaders, image, screens}` |
| `kill()` | | restarts the whole shell |

Caveat inherited from the platform: **the IPC socket can exit 0 even when the
call failed**, so callers must check the result string (the CLI does).

## The CLI — bin/omarchy-overlay-screensaver

A thin wrapper over `omarchy-shell overlayscreensaver <cmd>`, whose real job
is making the call work from **ssh and other non-login environments**.
Shader plumbing: `shader [NAME]` maps to `showShader(NAME, source)` and
`shaders` maps to the `shaders()` registry listing. The name is optional on
the CLI but is the **first** `showShader` argument over IPC — IPC methods
pass arguments positionally and the source tag always rides last. The CLI
checks the result string (not the exit code): `show/hide/toggle/shader/kill`
return `"ok"` or an error; `status`/`shaders` return their payload as the
result.


- A non-interactive ssh shell never sources `~/.bashrc`, so the session
  environment is missing. The CLI rebuilds `XDG_RUNTIME_DIR` (needed to find
  the IPC socket) and `OMARCHY_PATH`.
- Every method is logged by the plugin with a source tag; the CLI defaults it
  to `ssh:<user>@<client-ip>` or `local:<user>` so the shell log shows where a
  remote action came from (same audit pattern as `omarchy-remote-lock`).
- `kill` is the failsafe: it pings the shell, and if IPC is unreachable at
  all, falls back to `omarchy restart shell`, then
  `systemctl --user restart omarchy-shell.service`. The overlay's
  hidden-by-default init makes that always safe.

## Gotchas learned from the reference plugins

1. **Namespace collisions**: the layer-shell namespace must be unique per
   plugin or the compositor/other tooling can confuse surfaces. It's
   `omarchy-overlay-screensaver`, matching the convention
   `omarchy-background` / `omarchy-motion-background`.
2. **Never grab keyboard unconditionally**: `WlrKeyboardFocus.Exclusive` on
   an always-mapped surface would eat the whole session. Only the visible
   overlay surface holds it.
3. **`omarchy-shell` IPC exit codes lie**: parse the returned string.
4. **Untrusted input from disk**: if you later read config/state files with
   Process helpers, bound their size (a FIFO at the read path blocks forever;
   see `nosignal.motion-wallpaper`'s state-reading guards for the full
   pattern).
5. **The shell plugin directory hot-reloads** on save; if a change fails to
   apply, force it with `omarchy-shell shell rescanPlugins` or
   `omarchy restart shell`.

## How to extend

- **Idle trigger**: shell.json already has `idle.screensaver` (seconds), but
  that's owned by omarchy's built-in screensaver. To trigger on idle instead,
  either reuse `Quickshell.Hyprland` idle events or add a config key
  (`"idleSeconds"`) with a `Timer` poll — do not fight the built-in.
- **Auto-dismiss when the lock engages**: look up the lock service via
  `shell.serviceFor(...)` (see `kjlape.remote-lock`'s `lockService()` for the
  resolveEnabledId dance) and hide when it locks.
- **Animations / video**: swap the `Image` for `VideoOutput` /
  `QtMultimedia` (see `nosignal.motion-wallpaper`) or a QML animation. Keep
  the PanelWindow/layer/keyboardFocus scaffolding identical.
- **More shader hacks**: the rest of xscreensaver's `hacks/glx/glsl/`
  collection (or any shadertoy.com program) ports the same way `starnest`
  and `universeball` did — copy the frag, rename the input to
  `qt_TexCoord0`, add `time`/`aspect` uniforms, bake both stages, and
  register the name in `knownShaders` in Service.qml. The full plan and
  per-program checklist live in [roadmap.md](roadmap.md).
- **Bar widget toggle**: add a `barWidget` entry point to the manifest and a
  `BarWidget.qml` (see `lap.dock-recover` for the minimal pattern).

## Dev loop

**Recommended: a `file://` git remote.** The installed plugin at
`~/.config/omarchy/plugins/<id>/` is a real git clone, so point its `origin`
at the dev checkout — local dev then mimics a real remote with
`commit && push && pull`, and this is the most likely setup a dev will use:

```bash
git -C ~/.config/omarchy/plugins/kjlape.overlay-screensaver \
    remote add origin file://"$HOME"/dev/kjlape/omarchy-overlay-screensaver
# after committing in the dev checkout, pull in the installed clone:
git -C ~/.config/omarchy/plugins/kjlape.overlay-screensaver pull
```

Note: `git push` to the checked-out branch of a non-bare repo fails by
default. Simplest daily loop: commit in `~/dev/...`, then `git pull` in the
installed clone.

Alternative: edit code directly in the installed location, or symlink:

```bash
ln -s ~/dev/kjlape/omarchy-overlay-screensaver \
      ~/.config/omarchy/plugins/kjlape.overlay-screensaver
omarchy plugin enable kjlape.overlay-screensaver
omarchy plugin validate ~/.config/omarchy/plugins/kjlape.overlay-screensaver
# QML edits hot-reload on save; force with:
omarchy-shell shell rescanPlugins
# test recovery paths while the overlay is up:
omarchy-overlay-screensaver hide
omarchy-overlay-screensaver kill
```

Debugging: plugin `console.log` lines go to the shell's stdout/stderr. On
Omarchy 4 the shell runs under the uwsm compositor unit, so read them from
`journalctl --user -u "wayland-wm@hyprland.desktop.service"` — see
[troubleshooting.md](troubleshooting.md) for the full diagnostic ladder.
