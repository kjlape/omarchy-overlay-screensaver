# AGENTS.md

Guidance for AI coding agents (and humans in a hurry) working in this repo.

## What this repo is

A Quickshell **service plugin for omarchy-shell** (Omarchy 4+): it draws a
full-screen image overlay above every window via a Wayland layer-shell surface
on `WlrLayer.Top`, controllable over IPC from ssh/another TTY. Currently an
MVP — manual show/hide, no idle trigger.

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

## Key files

| File | Role |
|---|---|
| `Service.qml` | The whole plugin: overlay surfaces (`Variants` → `PanelWindow` per monitor), config lookup, `IpcHandler` (`show`/`hide`/`toggle`/`status`/`kill`). ~180 lines — read it in full. |
| `manifest.json` | Plugin identity `kjlape.overlay-screensaver`, service-only, `keepLoaded: true`. Schema is Omarchy's; validate with `omarchy plugin validate .` |
| `bin/omarchy-overlay-screensaver` | CLI wrapper. Its real job is rebuilding `XDG_RUNTIME_DIR`/`OMARCHY_PATH` so the IPC call works from non-interactive ssh. |
| `install.sh` / `uninstall.sh` | CLI-on-PATH only. The plugin itself is installed via `omarchy plugin add <repo> --enable` — these scripts never touch `~/.config/omarchy/`. |
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
omarchy-shell shell rescanPlugins         # force-reload if hot-reload didn't take
```

QML edits hot-reload on save when installed under `~/.config/omarchy/plugins/`.
Test recovery paths explicitly before committing: `hide`, `kill`, Escape,
click. Plugin `console.log` output lands in the shell's journal
(`journalctl --user -u "wayland-wm@hyprland.desktop.service"` — not
`-u omarchy-shell`, which doesn't exist on Omarchy 4; see
docs/troubleshooting.md).

State flags must never shadow final QML properties (`visible`, `anchors`,
…); the overlay's flag is `overlayVisible` for that reason — renaming it
back breaks the whole component load.

Do not edit anything under `/usr/share/omarchy/` — read it freely, never
write it. User config lives in `~/.config/omarchy/`.