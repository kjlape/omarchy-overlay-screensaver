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
the `@` prefix omarchy uses for some references). Currently one key:

- `image` — absolute path to the overlay image. Falls back to the
  current background via `readlink -f ~/.local/state/omarchy/current/background`
  (the same symlink `omarchy.background` follows).

shell.json hot-reloads on save, but `pluginConfig` is a binding over
`shell.shellConfig`, so config edits land live without a plugin rescan.

### State model — deliberately minimal

Exactly one bit: `visible: false`. No state file, no daemon, nothing that
survives a shell restart. That is the failsafe design: **the overlay always
initializes hidden**, so restarting the shell is a guaranteed recovery even if
the process is wedged. If you add state (e.g. remembering user-preferred
images), keep it out of the visibility path, or you break the recovery
guarantee.

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
- An `Item { focus: true }` with `Keys.onKeyPressed` → **any keystroke** to dismiss.
  This is the same key-catcher pattern the built-in clipboard panel uses.
  This is the same key-catcher pattern the built-in clipboard panel uses.
- An `Item { focus: true }` with `Keys.onKeyPressed` → **any keystroke** to dismiss.
  This is the same key-catcher pattern the built-in clipboard panel uses.

  This is the same key-catcher pattern the built-in clipboard panel uses.

The image is `Image.PreserveAspectCrop`, `asynchronous: true`, sourced from
`file://<path>`. Empty path → black (the PanelWindow `color`).

### IPC

`IpcHandler { target: "overlayscreensaver" }` exposes:

| Method | Args | Notes |
|---|---|---|
| `show(source)` | source tag for logging | returns `"ok"` |
| `hide(source)` | | |
| `toggle(source)` | | |
| `status()` | | JSON: `{visible, image, screens}` |
| `kill()` | | restarts the whole shell |

Caveat inherited from the platform: **the IPC socket can exit 0 even when the
call failed**, so callers must check the result string (the CLI does).

## The CLI — bin/omarchy-overlay-screensaver

A thin wrapper over `omarchy-shell overlayscreensaver <cmd>`, whose real job
is making the call work from **ssh and other non-login environments**:

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