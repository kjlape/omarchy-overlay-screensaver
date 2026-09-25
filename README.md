# omarchy-overlay-screensaver

A [Quickshell](https://quickshell.outfoxxed.me/) plugin for
[Omarchy](https://omarchy.org/) that draws a full-screen image overlay **above
every window** — fullscreen apps included, on every workspace, on every
monitor — via a Wayland layer-shell surface on `WlrLayer.Top`.

This is an MVP validating the overlay-screensaver direction: manual show/hide
only, no idle trigger yet.

```
omarchy-overlay-screensaver show     # image covers everything
omarchy-overlay-screensaver shader   # default GLSL hack (config `shader`, else starnest)
omarchy-overlay-screensaver shader universeball   # pick a specific GLSL hack
omarchy-overlay-screensaver shaders   # list the available GLSL hacks
<Esc>                                # dismiss (or click, or move the mouse, or CLI hide)
omarchy-overlay-screensaver status   # {"visible":false,"mode":"image","shader":"","shaders":[…],…}
```

## Dismissal & recovery

Four ways to get your screen back, in order:

1. **Escape** — the overlay grabs the keyboard exclusively while shown.
2. **Click anywhere** on the overlay.
3. **Move the mouse** — dismissal is driven by Qt motion events on the overlay
   surface itself; any ≥1 px move hides it (a 250 ms grace after show ignores
   the synthetic map-time motion, so it never dismisses itself).
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

While the overlay is shown the pointer is hidden (`Qt.BlankCursor`, a
per-surface null cursor — it comes back the moment the surface unmaps, even
on a crash) and the shader runs at the configured `fps` cap (default 30) to
limit idle battery drain.

## Autonomous idle mode (opt-in)

The overlay can also become an idle-activated screensaver that runs entirely
on its own clock — a private `IdleMonitor` (`ext-idle-notify-v1`), its own
toggle files, its own config. It deliberately **does not touch** the stock
Omarchy screensaver machinery: it creates no idle inhibitor, never touches
DPMS/suspend/lock schedules, and never writes Omarchy's stay-awake indicator
(it *reads* that indicator and goes quiet while Stay Awake is on).

**Order matters:** turn the stock screensaver off FIRST
(`omarchy toggle screensaver`), then opt in. Two screensavers at once break
the auto-lock (the stock one self-kills against our overlay).

```bash
omarchy toggle screensaver                       # 1. stock screensaver off
mkdir -p ~/.config/overlay-screensaver
cp <repo>/config/overlay-screensaver.example.json \
   ~/.config/overlay-screensaver/config.json
$EDITOR ~/.config/overlay-screensaver/config.json   # set "autoShow": true
omarchy-overlay-screensaver enable               # clears the off flag
omarchy-overlay-screensaver state                # off/hold gates + status
```

How it behaves:

- **`autoShow` defaults to false** — enabling the plugin never changes when
  your screen gets covered. Idle auto-show happens only after you set
  `"autoShow": true` and run `enable`.
- The screen covers after `idleSeconds` (default 300) of genuine seat idle
  with an observed activity→idle transition (a restart while unattended can
  never cover the screen).
- Keep `idleSeconds` **below** Omarchy's `idle.lock` (300 s default) — the
  lock hides us by protocol anyway, so a longer idle timeout just never fires.
- Manual `show`/`shader`/`hide` work regardless of these gates.
- Dismiss as usual (Escape/click/motion); the overlay re-arms on the next
  idle.

Toggles:

- `omarchy-overlay-screensaver disable` — never auto-show again (off flag);
  `enable` undoes it.
- `hold` / `unhold` — temporary stay-awake (presenting, watching).
- Omarchy's Stay Awake (bar indicator, `omarchy toggle idle`) is respected
  automatically and read-only.

`respectInhibitors` is on: a playing video or any `zwp_idle_inhibitor_v1`
holder suppresses auto-show. A session lock (hyprlock / omarchy lock) hides
the overlay entirely and it comes back after unlock — dismissal by pointer
still works. Do **not** use the menu's Screensaver button while this mode is
on: it bypasses the stock toggle (`force`) and will collide (drop that menu
entry in `~/.config/omarchy/omarchy-menu.jsonc` if you use it).

Full design, verified mechanics and the checklist: see
[moonshots/standalone-idle-mode.md](moonshots/standalone-idle-mode.md).

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
hack used as the **default** by the `shader` command (see below); an explicit
name argument (`omarchy-overlay-screensaver shader universeball`) always
wins. Run `omarchy-overlay-screensaver shaders` for the live list of
available hacks (all of them are also listed below).

## Shader hacks

`shader [NAME]` renders a ported [xscreensaver](https://www.jwz.org/xscreensaver/)
GLSL hack with a Qt `ShaderEffect` inside the same layer-shell surface —
in-process, so every dismissal path and the recovery guarantee still apply.
`NAME` picks the hack (default: the `shader` config key, else `starnest`);
unknown names are rejected without showing anything. Current ports:

- **starnest** — Star Nest by Kali
  ([shadertoy.com/view/XlfGRj](https://www.shadertoy.com/view/XlfGRj), MIT;
  upstream xscreensaver ships it as `hacks/glx/glsl/starnest.glsl`) —
  a volumetric kaliset fractal flythrough.
- **universeball** — Universe Ball 2 by Matt Vianueva
  ([shadertoy.com/view/WcGcWV](https://www.shadertoy.com/view/WcGcWV), MIT
  relicensed by permission; upstream xscreensaver ships it as
  `hacks/glx/glsl/universeball.glsl`) — a marble-planet miniverse flythrough.
- **topologica** — Topologica by otaviogood
  ([shadertoy.com/view/4djXzz](https://www.shadertoy.com/view/4djXzz), CC0;
  upstream xscreensaver ships it as `hacks/glx/glsl/topologica.glsl`) —
  a slow orbit around a pulsing volumetric noise nebula.
- **downfall** — Downfall by Matt Vianueva
  ([shadertoy.com/view/w3sBWl](https://www.shadertoy.com/view/w3sBWl), MIT
  relicensed by permission; upstream xscreensaver ships it as
  `hacks/glx/glsl/downfall.glsl`) — cascading pillar-like structures in a
  raymarched descent.
- **trizm** — Trizm by Matt Vianueva
  ([shadertoy.com/view/3fcBD8](https://www.shadertoy.com/view/3fcBD8), MIT
  relicensed by permission; upstream xscreensaver ships it as
  `hacks/glx/glsl/trizm.glsl`) — a twisting tunnel of triangle-wave
  conduits (inspired by @OldEclipse's "Cyber Conduits"), raymarched with
  an `asin(sin(x))` triangle-wave distortion.
- **stardome** — Stars and galaxy by mrange
  ([shadertoy.com/view/stBcW1](https://www.shadertoy.com/view/stBcW1), CC0;
  upstream xscreensaver ships it as `hacks/glx/glsl/stardome.glsl`) —
  a slow-panning night-sky dome: layered starfield, galaxy band, moon,
  spherical grid, and horizon glow over a black ground plane; loops on a
  gentle 30 s fade cycle.
- **rigrekt** — Rig Rekt by Matt Vianueva
  ([shadertoy.com/view/3XKfDV](https://www.shadertoy.com/view/3XKfDV), MIT
  relicensed by permission; upstream xscreensaver ships it as
  `hacks/glx/glsl/rigrekt.glsl`) — a tunnel of boxes with a twisting
  pattern of rings.
- **xmatrix** — Matrix (digital rain), Jamie Zawinski
  (xscreensaver's `hacks/xmatrix.c`, © 1999–2018, jwz BSD-style notice) —
  the only port here that isn't a shader upstream: the C screensaver's
  falling-glyph grid reimplemented as a stateless fragment shader, with
  hand-drawn 5×7 katakana-ish glyphs (the upstream glyph bitmaps are
  license-ambiguous, so none are shipped or sampled). See
  [docs/roadmap.md](docs/roadmap.md#non-glsl-sources-phase-1b-reimplementations-from-the-c-hacks).
- **xmatrixcrt** *(experimental fork)* — the same xmatrix engine dressed as a
  90s CRT: barrel curvature on the grid, phosphor glow, aperture-grille mask,
  scanlines, vignette, mains-hum flicker, and a dim beige bezel lit only by
  the tube's own glow. All constants are in the `CRT-TUNING` block of
  `shaders/xmatrixcrt.frag`; the glyph engine is a frozen copy of
  `xmatrix.frag`.

GLSL sources live in `shaders/`; the baked `.qsb` files are rebuilt with
`/usr/lib/qt6/bin/qsb --glsl "100,120,150,330,440" <in> -o <in>.qsb`.
See [docs/roadmap.md](docs/roadmap.md) for the full porting plan, recipe,
and the porting-tips list (coordinate conversion, testing loop) learned
from the ports so far.

## IPC surface

`omarchy-shell overlayscreensaver <show|showShader <shader> <source>|shaders|hide|toggle|status|kill>`
— the CLI is a wrapper that rebuilds the session environment for
non-interactive ssh callers and adds shader-name handling (`showShader`'s
first argument is the shader name; empty = configured default).

## Docs

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how it works and how to
  extend it. **Read this first if you're changing the code.**
- [docs/analysis.md](docs/analysis.md) — the pre-implementation research that
  validated the approach (why layer-shell is the only mechanism that works).
- [docs/quickref.md](docs/quickref.md) — one-page summary of the research.

## License

MIT — see [LICENSE](LICENSE).