# Moonshot: run the xscreensaver hack collection in the overlay

> Goal: support **all** classic xscreensaver hacks (xflame, pyro, gluco,
> phosphor, … — ~270 as of 6.16) as content for the overlay — not just
> static images — while keeping the plugin's core guarantees (overlay
> above everything, always starts hidden, `kill` fully recovers).

Not implemented. This is a researched design sketch.

> **Update:** the *complement* path described under "Why not alternatives"
> (porting the GLSL/shadertoy hacks to a QML `ShaderEffect`) is now real —
> `starnest` ("Star Nest" by Kali, MIT) is ported and shipped, driven by the
> `shader` CLI verb / `showShader` IPC. See `shaders/` and the "Shader
> content" section of [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md).
> The Xvfb offscreen-stage architecture below remains the moonshot for the
> other ~250 hacks.

## Licensing: verified against the 6.16 source (Sep 2026)

The hacks are OSS and **permissively licensed — deliberately not GPL**.

- jwz's own code carries a BSD-like notice ("Permission to use, copy,
  modify, distribute, and sell… provided that the copyright notice appear
  in all copies").
- `README.hacking` states it outright: *"The GNU GPL is not compatible
  with the rest of XScreenSaver"* — contributions must be BSD-like.
- Practical consequence for us: we may run, wrap, patch, or even fork and
  relicense hack code freely, with attribution kept intact. Nothing
  copyleft contaminates the plugin.
- Caveat: the collection is ~270 hacks by dozens of authors (321 config
  files in 6.16), each file carrying its own header — check per-file if we
  ever copy code rather than merely exec the packaged binaries (which this
  design does).

Related upstream facts worth knowing (all checked in the 6.16 tarball):

- The hacks are ~270 standalone C programs built on the `screenhack`
  framework, drawing through **jwxyz**, jwz's portability layer with
  backends for X11, macOS, iOS, Android — **no Wayland backend exists**.
  On Wayland, hacks still render via XWayland; jwz's Wayland support is
  daemon-side only (idle/blanking/DPMS protocols). This is independent
  confirmation of the "no place to put them under Wayland" constraint
  below.
- Since **6.14** xscreensaver can also run **shadertoy.com programs** as
  screen savers, and ships ~18 GLSL hacks (`stardome`, `topologica`, …).
  Those are per-frame fragment shaders — trivially portable to a QML
  `ShaderEffect` as a complement to this design (see "Why not
  alternatives").
- jwz publishes no public git repo; tarballs only. The
  `Zygo/xscreensaver` GitHub mirror tracks each release if you want to
  grep the tree without downloading tarballs.

## Why this is hard (the constraints that shape it)

- **xscreensaver hacks are X11 programs.** Each is a standalone binary
  (installed under `/usr/lib/xscreensaver/`) that draws into an X11 window,
  typically the root window via `-root`. They don't need the xscreensaver
  daemon — any hack can be spawned directly. That's the good news.
- **Wayland has no place to put them.** Wayland has no screensaver protocol
  and no cross-client surface reparenting; jwz's own writeup is the canonical
  statement of the problem. A toplevel window — even an XWayland one — cannot
  be stacked above layer-shell surfaces, and Hyprland window rules have no
  z-order. So "run it under XWayland somewhere visible" is a dead end; only
  our layer-shell surface can overlay everything.
- **`-window-id` is gone.** Modern xscreensaver removed the option to draw
  into a caller-provided window ("it never worked right" — jwz). Older
  versions supported it; xsecurelock's `saver_xscreensaver` module is prior
  art. Practical consequence: the shim must give each hack **its own private
  X server and use `-root`**, which is cleaner anyway.

Conclusion: the only viable architecture is an **offscreen X stage whose
frames are relayed into the existing layer-shell surface**. The hack runs
where it's happy (its own X server); the overlay stays where it must (our
layer-shell surface, in the shell process).

## Architecture: offscreen X stage → frame capture → overlay surface

```
┌─ plugin (in shell process) ─────────────────────────────────┐
│ IPC: show-hack "xflame" → spawn child process tree:          │
│   Xvfb :99  -screen 0 WxHx24  (GLX enabled, private)         │
│   DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 \                      │
│     /usr/lib/xscreensaver/xflame -root                       │
│   ffmpeg -f x11grab -draw_mouse 0 -video_size WxH \          │
│          -framerate 25 -i :99  → frames                      │
│                                                              │
│ overlay PanelWindow (unchanged, WlrLayer.Top):               │
│   QML Image / Video fed by the frame stream                  │
│   dismissal ladder unchanged (key / click / mouse / IPC/kill)│
└──────────────────────────────────────────────────────────────┘
```

The layer-shell half of the plugin stays exactly as it is. Only the content
source changes: from "a file path" to "a live frame stream."

## Frame delivery to QML (in order of implementation difficulty)

1. **MVP — frame swap.** `ffmpeg … /run/user/$UID/xss-overlay/frame.png`
   (or a numbered sequence) into tmpfs; a QML `Timer` at ~20–25 fps reloads
   an `Image` with `cache: false` and a cache-busting counter
   (`source: "file://…?v=" + counter`). Trivial to build; enough to validate
   the whole pipeline. PNG encode is the cost — fine at ~1080p.
2. **Upgrade — hardware-decoded video.** ffmpeg → mjpeg or h264 into a
   fifo/socket, consumed by a QtMultimedia `Video` inside the surface
   (udp://127.0.0.1:port works). Lower CPU, more moving parts.
3. **Long shot.** A small C++ Quickshell extension exposing an
   SHM-backed texture. Max fidelity, most work; only if the QML paths
   disappoint.

## Plugin changes required

- New IPC methods alongside `show`/`hide`:
  - `show-hack <name>` — start the process tree and show the overlay
  - `list-hacks` — scrape `/usr/lib/xscreensaver/` for available hacks
- **Process-group hygiene is load-bearing** (protects the recovery
  guarantee):
  - Launch Xvfb / hack / ffmpeg under `setsid` with a known PGID.
  - Record the PGID in `$XDG_RUNTIME_DIR/xss-overlay.pgid`.
  - `kill -- -PGID` on every hide, on `Component.onDestruction`, and as a
    stale-guard at every `show-hack` (same state-file guard pattern as the
    nosignal.motion-wallpaper reference plugin).
  - Then `overlayscreensaver kill` / shell restart still fully recovers:
    overlay starts hidden, no orphan X servers or spinners left behind.
- Config (through `cfg(name, fallback)`), e.g.:
  - `defaultHack` — hack to run when `show-hack` has no argument
  - `hackResolution` — cap the virtual X screen (see gotchas)
  - `hackFps`

## Gotchas

- **GL hacks need GLX in Xvfb**: use `Xvfb :99 -screen 0 WxHx24` with
  `LIBGL_ALWAYS_SOFTWARE=1` (mesa swrast). Software GL at 4K plus x11grab is
  real CPU — cap the virtual screen around 1080p–1440p and let QML scale.
- **Multi-monitor**: one Xvfb sized to the largest screen; every per-monitor
  surface renders the same stream (`Image` scales). N hacks for N monitors
  is a later refinement.
- **Latency** is a few frames end-to-end — irrelevant for a screensaver.
- A few hacks sulk without the daemon; a tiny env shim
  (`XSCREENSAVER_WINDOW`, etc.) handles the outliers.
- Same pipeline = arbitrary X11 programs generally; swapping x11grab for
  `wf-recorder`/PipeWire screencast would even allow arbitrary Wayland
  clients running on a hidden workspace.

## Why not alternatives

- **XWayland on screen**: can't stack above layer-shell (bar, other
  overlays) or even above fullscreen toplevels reliably; would break the
  plugin's whole reason to exist.
- **Reimplementing hacks in QML/shaders**: reasonable as a complement for
  your 3–4 favorites — and cheaper than it sounds, because since 6.14 the
  GLSL/shadertoy hacks (`stardome`, `topologica`, …) plus the whole
  Shadertoy corpus port nearly verbatim into a `ShaderEffect` inside the
  existing overlay surface. But no path to all ~270 hacks, and the classic
  2D XCopyArea-era hacks (xmatrix, munch, deco, …) have no shader form.
- **Bundling old xscreensaver for `-window-id`**: fighting removed
  functionality; private-Xvfb + `-root` is simpler and upstream-supported.

## References

- jwz, "Wayland and screen savers" — https://www.jwz.org/blog/2023/09/wayland-and-screen-savers/
- xscreensaver changelog (removal of `-window-id`) — https://www.jwz.org/xscreensaver/changelog.html
- google/xsecurelock `saver_xscreensaver` (prior art for embedding hacks) — https://github.com/google/xsecurelock
- Repo context: [../docs/analysis.md](../docs/analysis.md) (why layer-shell is
  the only overlay mechanism), [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md)