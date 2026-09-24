# Quick Reference

> Pre-implementation research summary. The implementation lives in this repo;
> see [ARCHITECTURE.md](ARCHITECTURE.md) for the built version.

## Question
Can an omarchy (Quickshell) plugin draw an overlay (screensaver) on top of everything — regardless of workspace or fullscreen apps?

## Answer: Yes

Use a **Quickshell `PanelWindow`** attached to the Wayland layer-shell with `WlrLayer.Top`:

```qml
PanelWindow {
  WlrLayershell.namespace: "omarchy-screensaver"
  WlrLayershell.layer: WlrLayer.Top       // Above all windows, including fullscreen
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  anchors { top: true; bottom: true; left: true; right: true }
}
```

## Why fullscreen hyprland windows don't work
- Hyprland window rules have **no z-order field** (hard constraint in the compositor)
- Client fullscreen is **workspace-local** (vanishes on workspace switch)
- Wayland forbids **cross-client surface reparenting**
- Only layer-shell clients render below/above all toplevels

## Architecture
```
WLR Layer Stack (bottom → top):
┌──────────────────────┐ WlrLayer.Background  ← omarchy.background (static wallpaper)
├──────────────────────┤
├──────────────────────┤ WlrLayer.TopLevel    ← fullscreen apps / regular toplevels
├──────────────────────┤
├──────────────────────┤ WlrLayer.Top        ← YOUR SCREENSAVER (above everything)
└──────────────────────┘
```

## Reference implementation
The motion-wallpaper plugin at `~/.config/omarchy/plugins/nosignal.motion-wallpaper/` already proves this pattern. Just change:
1. `WlrLayershell.namespace: "omarchy-motion-background"` → `"omarchy-screensaver"`
2. `WlrLayershell.layer: WlrLayer.Background` → `WlrLayer.Top`
3. Replace `VideoOutput` with your renderer

## Triggering
Use `Quickshell.Settings.idle.screensaver` (seconds since idle) or `Quickshell.Hyprland` events to show/hide the overlay.

## See full analysis
`analysis.md` for complete details on why, how, and what to watch for.

## Troubleshooting quick hits
- `Target not found` ⇒ Service.qml failed to compile; check
  `journalctl --user -u "wayland-wm@hyprland.desktop.service" | grep "plugin load failed"`
- `omarchy plugin list` shows config state, not load state — "enabled" ≠ loaded
- Never shadow final QML properties (`visible`!) on the root Item — use `overlayVisible`
- Installed copy is a git clone with a `file://` origin pointing at the dev
  repo — after editing in `~/dev`, commit there, then `git pull` in the
  installed clone so QML edits land (pull without a prior commit does nothing)
- Hot-reload can serve a stale broken compile → `omarchy restart shell` (always safe; overlay starts hidden)
- IPC exits 0 on failure — check the result string, not the exit code

See `troubleshooting.md` for the full diagnostic ladder.
