# omarchy-overlay-screensaver

A [Quickshell](https://quickshell.outfoxxed.me/) plugin for
[Omarchy](https://omarchy.org/) that draws a full-screen image overlay **above
every window** — fullscreen apps included, on every workspace, on every
monitor — via a Wayland layer-shell surface on `WlrLayer.Top`.

This is an MVP validating the overlay-screensaver direction: manual show/hide
only, no idle trigger yet.

```
omarchy-overlay-screensaver show     # image covers everything
omarchy-overlay-screensaver shader   # "Star Nest" flies through a fractal nebula
<Esc>                                # dismiss (or click, or move the mouse, or CLI hide)
omarchy-overlay-screensaver status   # {"visible":false,"mode":"image","screens":N,…}
```

## Dismissal & recovery

Four ways to get your screen back, in order:

1. **Escape** — the overlay grabs the keyboard exclusively while shown.
2. **Click anywhere** on the overlay.
3. **Move the mouse** — the cursor is polled via `hyprctl cursorpos` while the
   overlay is shown, and any movement dismisses it.
4. **CLI from ssh or another TTY** (no display access needed):

   ```bash
   omarchy-overlay-screensaver hide
   ssh box omarchy-overlay-screensaver hide
   ```

5. **Failsafe — guaranteed recovery.** The overlay lives inside the
   omarchy-shell process and always starts hidden, so restarting the shell can
   never come back overlaid:

   ```bash
   ssh box omarchy-overlay-screensaver kill   # restarts the omarchy shell
   # if the CLI itself is unreachable:
   ssh box omarchy restart shell
   ```

There is no daemon and no persisted state. `kill` is not graceful — it is the
break-glass option.

## Install

The plugin and CLI are separate installs, same split as `omarchy-remote-lock`:

```bash
# 1. Plugin: clone into the user plugin directory and enable
omarchy plugin add https://github.com/kjlape/omarchy-overlay-screensaver.git --enable
#    (or, for a local checkout:)
#    git clone ~/dev/kjlape/omarchy-overlay-screensaver ~/.config/omarchy/plugins/kjlape.overlay-screensaver
#    omarchy plugin enable kjlape.overlay-screensaver

# 2. CLI on PATH
./install.sh
```

`omarchy plugin add` clones to `~/.config/omarchy/plugins/<id>/`, validates the
manifest, registers the service in `~/.config/omarchy/shell.json`, and the
shell hot-reloads. Force a reload if needed with `omarchy restart shell`.

For local development the clone's `origin` can simply point at the dev
checkout with a `file://` URL (`git -C ~/.config/omarchy/plugins/<id> remote
add origin file://$HOME/dev/kjlape/omarchy-overlay-screensaver`); commit in
the dev repo, `git pull` in the installed clone, and QML edits hot-reload.
Force a reload if needed with `omarchy restart shell`.

Uninstall: `./uninstall.sh` + `omarchy plugin remove kjlape.overlay-screensaver`.

## Config (optional)

In `~/.config/omarchy/shell.json`, `plugins[]`:

```json
{
  "id": "kjlape.overlay-screensaver",
  "image": "/home/you/Pictures/x.png",
  "shader": "starnest"
}
```

With no `image`, the overlay falls back to the current omarchy background
(`~/.local/state/omarchy/current/background`). `shader` selects the GLSL
hack used by the `shader` command (see below) — currently only `starnest`.

## Shader hacks

`shader` renders a ported [xscreensaver](https://www.jwz.org/xscreensaver/)
GLSL hack with a Qt `ShaderEffect` inside the same layer-shell surface —
in-process, so every dismissal path and the recovery guarantee still apply.
The current port is **Star Nest** by Kali
([shadertoy.com/view/XlfGRj](https://www.shadertoy.com/view/XlfGRj), MIT;
upstream xscreensaver ships it as `hacks/glx/glsl/starnest.glsl`) — a
volumetric kaliset fractal flythrough. GLSL sources live in `shaders/`;
the baked `.qsb` files are rebuilt with
`/usr/lib/qt6/bin/qsb --glsl "100,120,150,330,440" <in> -o <in>.qsb`.

## IPC surface

`omarchy-shell overlayscreensaver <show|showShader|hide|toggle|status|kill>` — the CLI is
a wrapper that rebuilds the session environment for non-interactive ssh
callers.

## Docs

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how it works and how to
  extend it. **Read this first if you're changing the code.**
- [docs/analysis.md](docs/analysis.md) — the pre-implementation research that
  validated the approach (why layer-shell is the only mechanism that works).
- [docs/quickref.md](docs/quickref.md) — one-page summary of the research.

## License

MIT — see [LICENSE](LICENSE).