# Omarchy / Quickshell Overlay Screensaver — Technical Analysis

## TL;DR

**Yes, an omarchy (Quickshell) plugin can absolutely draw an overlay that covers everything — fullscreen apps included.**

The mechanism: a **Quickshell `PanelWindow`** attached to the Wayland layer-shell interface with `WlrLayer.Top`. This is *not* a window-rule hack; it's the compositor's intended mechanism for surfaces that render above all toplevels.

The reference implementation is the **Motion Wallpaper plugin** (`nosignal.motion-wallpaper`), which demonstrates the exact same pattern but at `WlrLayer.Background` instead of `WlrLayer.Top`.

---

## Why a fullscreen hyprland window is a "hack at best"

This conclusion comes from [Motion-Wallpaper approach doc](https://github.com/28allday/Motion-Wallpaper-Omarchy/blob/main/docs/approach.md) which documents the dead-ends tried before arriving at the final architecture:

### 1. Window rules cannot control z-order

Hyprland window rules have **zero** support for z-ordering. The valid effect list in `WindowRuleEffectContainer.cpp` contains no `below`, `above`, or `zorder` field. A regular toplevel can never be ordered beneath other regular toplevels — the only surfaces Hyprland places under everything are **layer-shell** surfaces.

```
Valid Hyprland window rule effects:
  - resize_to_fit
  - transparent
  - hint
  - [NO z-order, NO below/above]
```

### 2. Client fullscreen is workspace-local

A fullscreen toplevel covers only its own workspace. Switch to another workspace and the "wallpaper" disappears. This is a Wayland protocol constraint, not a Hyprland config bug.

### 3. No Wayland surface reparenting

There is no cross-client surface reparenting in Wayland. A client's toplevel belongs to that client; only the compositor places it. The only "theoretical workaround" (keep the client alive on a hidden workspace and pixel-copy via screencopy) is rejected as high-latency scaffolding around a solved problem.

---

## The only real wallpaper/overlay mechanism: `WlrLayershell`

Wayland restricts surface placement to the compositor. The only way to render something below *all* windows, on *all* workspaces, is a **layer-shell client**:

```
WLR Layer Stack (bottom to top):
  ┌─────────────────────────────────┐  WlrLayer.Background
  │ Background (wallpaper)         │
  ├─────────────────────────────────┤  WlrLayer.TopLevel
  │ Top-level (fullscreen apps)     │
  ├─────────────────────────────────┤  WlrLayer.Top
  │ Top-layer (omarchy overlay)    │  ← Screensaver here
  │ (bar, overlays, screensaver)    │
  └─────────────────────────────────┘
```

Omarchy already uses this pattern in two first-party/third-party plugins:

| Plugin | Namespace | Layer | Position |
|--------|-----------|-------|----------|
| `omarchy.background` | `omarchy-background` | `WlrLayer.Background` | Beneath all windows (static wallpaper) |
| `nosignal.motion-wallpaper` | `omarchy-motion-background` | `WlrLayer.Background` | Above static wallpaper (video) |
| **your screensaver** | `omarchy-screensaver` | **`WlrLayer.Top`** | **Above everything** |

---

## Quickshell `PanelWindow` + `WlrLayershell` API

The Quickshell docs show the pattern directly:

```qml
// Reference: https://quickshell.org/docs/v0.1.0/types/Quickshell.Wayland/WlrLayershell/
PanelWindow {
  WlrLayershell.namespace: "omarchy-<your-namespace>"
  WlrLayershell.layer: WlrLayer.Top       // Controls stacking
}
```

Properties:
- **`WlrLayershell.namespace`** — Unique identifier for the layer shell. Must be distinct from other plugins to avoid collisions.
- **`WlrLayershell.layer`** — Which Wayland layer to bind to. Defaults to `WlrLayer.Top`.
- **`WlrLayershell.keyboardFocus`** — Which processes get keyboard focus. Set to `WlrKeyboardFocus.None` for a screensaver.
- **`ExclusionMode`** — How the panel interacts with pointer events.

---

## How omarchy-shell's architecture handles overlays

The omarchy-shell (Quickshell) runs as a single long-lived process:

```
~/.config/omarchy/shell.json              # User overrides: bar, plugins, idle
~/.config/omarchy/plugins/<plugin-id>/   # User-owned plugins (hot-reload)
$OMARCHY_PATH/config/omarchy/shell.json  # Canonical defaults
```

Each plugin declares itself in `manifest.json`:

```json
{
  "schemaVersion": 1,
  "id": "my.screensaver",
  "name": "Screensaver Overlay",
  "version": "1.0.0",
  "description": "Overlay screensaver triggered by idle time",
  "kinds": ["service", "bar-widget"],
  "entryPoints": {
    "service": "Service.qml",
    "barWidget": "BarWidget.qml"
  },
  "barWidget": {
    "displayName": "Screensaver",
    "description": "Toggle the screen overlay screensaver",
    "category": "Desktop",
    "defaultSection": "left",
    "allowMultiple": false
  }
}
```

**The shell hot-reloads on save** — no restart needed for layout changes. Plugin code edits require `omarchy-restart-shell` or `ipc call shell rescanPlugins`.

---

## Architecture: Motion Wallpaper as Reference

The motion-wallpaper plugin (`~/.config/omarchy/plugins/nosignal.motion-wallpaper/`) is the exact reference for what you'd build. Here's the relevant pattern from `Panel.qml`:

```qml
PanelWindow {
  id: panel
  
  screen: modelData        // Bound to a Quickshell.Screens screen
  
  visible: !remapGuard.remapping  // Doesn't render on parked screens
  
  anchors { top: true; bottom: true; left: true; right: true }
  
  color: "transparent"
  updatesEnabled: true  // Critical: prevents black desktop after sleep
  
  property bool maskReady: false  // Controls reveal transition trigger
  
  WlrLayershell.namespace: "omarchy-motion-background"
  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore
  
  // ... rendering (Image, VideoOutput, QML Canvas, etc.) ...
}
```

**For a screensaver**, you'd change exactly these three things:

1. `WlrLayershell.namespace: "omarchy-screensaver"` — unique namespace
2. `WlrLayershell.layer: WlrLayer.Top` — render above all windows (or `WlrLayer.TopLevel` if you want it visible across workspaces during fullscreen)
3. Replace the `VideoOutput` renderer with whatever you want (e.g., a looping QML animation, a WebGL shader via `QtQmlCanvas`, a GIF player, etc.)

---

## Triggers: How would the screensaver know when to activate?

Quickshell already has idle state exposed in `shell.json`:

```json
{
  "idle": {
    "screensaver": 300,    // seconds before activating screensaver
    "lock": 600           // seconds before locking
  }
}
```

The shell exposes `Quickshell.Settings.idle.screensaver` and `Quickshell.Settings.idle.lock` in QML. The service would:

```qml
// Service.qml pattern
Component.onCompleted: {
  // Watch the idle time, activate at the threshold
  idleTimer.restart()
}

Timer {
  id: idleTimer
  interval: 1000  // 1 second
  start: true
  
  onTriggered: {
    if (root.shouldShow && root.overlayVisible) return
    
    if (Quickshell.Settings.idle.screensaver <= root.idleTime) {
      root.overlayVisible = true
    }
  }
}

property bool overlayVisible: false
property bool shouldShow: root.enabled && !root.paused
```

The service would also need to listen for Hyprland focus events (`Quickshell.Hyprland`) to:
- **Resume** when the user moves focus to a window
- **Pause** when a window enters fullscreen
- **Stay active** while idle

---

## Complete project layout

```
~/.config/omarchy/plugins/my.screensaver/
├── manifest.json          # Plugin manifest (required)
├── Service.qml            # Timer logic, IPC handlers, state
├── Panel.qml              # WlrLayer.Top overlay (required entry)
├── BarWidget.qml          # Optional: bar icon to toggle pause/stop
├── QmlResources/
│   └── screensaver-anim.qml  # Custom animation (looping shapes, shaders, etc.)
└── README.md              # Documentation
```

---

## Comparison: omarchy-shell plugin vs. standalone approach

| Approach | Rendering | Lifecycle | Integration | Barrier |
|----------|-----------|-----------|-------------|---------|
| Fullscreen hyprland app | X11/Wayland toplevel | `omarchy-restart` | None (window-rule hack) | ❌ Window rules have no z-order; workspace-local |
| Native `WlrLayershell` client | Arbitrary (any toolkit) | `systemd` / `pkinit` | Manual IPC to control | ❌ Re-invents shell, bar, idle hooks |
| omarchy-shell plugin | QML (any renderer) | Shell process (long-lived) | Bar widget, IPC, hot-reload, shell.json config | ✅ **The right tool** |
| Shell plugin + external daemon | External | `systemd` timer | Shell IPC for control | ❌ Unnecessary for simple cases |

**Verdict:** A shell plugin is the cleanest approach because it:
- Lives in the same IPC domain as idle/lock state
- Gets bar widget integration for free
- Hot-reloads on QML save (no shell restart)
- Survives shell restart (state persists in `~/.local/state/`)
- Uses the same pattern proven by `motion-wallpaper` and `omarchy.background`

---

## Sources

- [Motion-Wallpaper approach doc (local copy in scratch)](https://github.com/28allday/Motion-Wallpaper-Omarchy/blob/main/docs/approach.md) — The detailed dead-end analysis documenting why fullscreen hyprland windows cannot work as wallpaper
- [Quickshell WlrLayershell docs](https://quickshell.org/docs/v0.1.0/types/Quickshell.Wayland/WlrLayershell/) — The `PanelWindow` + `WlrLayershell` API
- [`nosignal.motion-wallpaper` plugin](~/.config/omarchy/plugins/nosignal.motion-wallpaper/Panel.qml) — The reference implementation using `WlrLayer.Background`
- [Omarchy shell plugins guide](Omarchy shell plugin docs, installed at /usr/share/omarchy/shell/plugins/README.md) — Shell architecture, plugins.md, and service patterns
- [Hyprland background layer behavior](/usr/share/omarchy/shell/plugins/background/Background.qml) — The first-party background plugin as the template pattern

---

## Decision

**Yes, an omarchy/Quickshell plugin can draw an overlay on top of everything.** The mechanism is `PanelWindow` + `WlrLayershell` with `WlrLayer.Top`. This is not a hack — it's the Wayland layer-shell mechanism exactly as intended. The motion-wallpaper plugin at `~/.config/omarchy/plugins/nosignal.motion-wallpaper/` is a working template showing every detail of how this works.
