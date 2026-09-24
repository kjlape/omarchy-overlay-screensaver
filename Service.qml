import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// MVP validation of the overlay-screensaver direction: a layer-shell surface
// on WlrLayer.Top, which Hyprland stacks above ALL toplevels — fullscreen
// windows included, on every workspace — and above the bar. One PanelWindow
// per monitor, driven by a single `visible` flag.
//
// Dismissal (in order of preference):
//   1. Escape key  — the overlay grabs the keyboard exclusively while shown
//   2. Any click   — MouseArea below
//   3. Mouse move  — cursor position polled via `hyprctl cursorpos` while shown
//   4. IPC: `omarchy-shell overlayscreensaver hide` (works from ssh/TTY,
//      see bin/omarchy-overlay-screensaver)
//   5. Nuke option: `omarchy-shell overlayscreensaver kill` or
//      `omarchy restart shell` — the overlay starts hidden, so a shell
//      restart always recovers the screen. Nothing here runs outside the
//      shell process; there is no daemon that can wedge the overlay.
//
// Config (shell.json plugins[] entry):
//   { "id": "kjlape.overlay-screensaver", "image": "/path/to/img.png" }
// With no `image`, falls back to the current omarchy background.

Item {
  id: root

  // ---- injected by shell.qml (_syncServices/ensureService) ----
  property var shell: null
  property var pluginRegistry: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string pluginId: "kjlape.overlay-screensaver"
  readonly property string home: Quickshell.env("HOME")
  readonly property string backgroundLink: home + "/.local/state/omarchy/current/background"

  property bool overlayVisible: false
  property string imagePath: ""

  // Mouse-move dismissal: while the overlay is shown, poll `hyprctl cursorpos`
  // and hide as soon as the cursor moves from its position at show time.
  // The empty string marks "baseline not yet sampled".
  property string cursorBaseline: ""

  // ---- config from shell.json ----
  readonly property var pluginConfig: {
    var cfg = shell && shell.shellConfig ? shell.shellConfig : null
    if (!cfg || !Array.isArray(cfg.plugins)) return ({})
    for (var i = 0; i < cfg.plugins.length; i++) {
      var e = cfg.plugins[i]
      if (e && String(e.id).replace(/^@/, "") === pluginId) return e
    }
    return ({})
  }

  function cfg(name, fallback) {
    var v = pluginConfig ? pluginConfig[name] : undefined
    return (v === undefined || v === null) ? fallback : v
  }

  // Config image wins; otherwise resolve the current background once on load.
  readonly property string configuredImage: String(cfg("image", "")).trim()

  function refreshImage() {
    if (root.configuredImage !== "") {
      root.imagePath = root.configuredImage
      return
    }
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function show(source): string {
    refreshImage()
    root.cursorBaseline = "" // resample cursor position on each show
    root.overlayVisible = true
    console.log("overlay-screensaver: shown source=" + String(source || "unknown")
      + " image=" + (root.imagePath || "(none)"))
    return "ok"
  }

  function hide(source): string {
    root.overlayVisible = false
    console.log("overlay-screensaver: hidden source=" + String(source || "unknown"))
    return "ok"
  }

  function toggle(source): string {
    return root.overlayVisible ? root.hide(source) : root.show(source)
  }

  function kill(): string {
    // Last-resort recovery: restart the whole shell. The overlay starts
    // hidden, so the screen is guaranteed to come back.
    if (!killProc.running) killProc.running = true
    return "ok"
  }

  function status(): string {
    return JSON.stringify({
      visible: root.overlayVisible,
      image: root.imagePath,
      screens: Quickshell.screens.length
    })
  }

  Process {
    id: readlinkProc
    command: ["bash", "-c", "readlink -f \"$1\"", "--", root.backgroundLink]
    stdout: StdioCollector {
      onStreamFinished: {
        var p = String(text || "").trim()
        if (p !== "") root.imagePath = p
      }
    }
  }

  Timer {
    id: cursorTimer
    interval: 300
    running: root.overlayVisible
    repeat: true
    onTriggered: if (!cursorProc.running) cursorProc.running = true
  }

  Process {
    id: cursorProc
    // The shell process runs without HYPRLAND_INSTANCE_SIGNATURE (uwsm strips
    // it), so plain `hyprctl` fails here. Derive the signature from
    // XDG_RUNTIME_DIR/hypr/ at call time (newest instance wins).
    command: ["bash", "-c",
      "d=\"$XDG_RUNTIME_DIR/hypr\"; " +
      "sig=$(ls -t \"$d\" 2>/dev/null | head -n1); " +
      "if [ -z \"$sig\" ]; then echo \"no hypr instance\" >&2; exit 1; fi; " +
      "HYPRLAND_INSTANCE_SIGNATURE=\"$sig\" hyprctl cursorpos"]
    stderr: StdioCollector {
      onStreamFinished: if (String(text).trim() !== "")
        console.log("overlay-screensaver: cursorpos stderr: " + String(text).trim())
    }
    stdout: StdioCollector {
      onStreamFinished: {
        var pos = String(text || "").trim()
        if (pos === "") return
        if (root.cursorBaseline === "") {
          root.cursorBaseline = pos
          return
        }
        if (pos !== root.cursorBaseline) {
          console.log("overlay-screensaver: hidden source=mouse-move")
          root.overlayVisible = false
        }
      }
    }
  }

  Process {
    id: killProc
    // The overlay lives in the shell process and starts hidden, so restarting
    // the shell is a full, guaranteed recovery path.
    command: ["bash", "-c", "omarchy restart shell >/dev/null 2>&1 &"]
  }

  IpcHandler {
    target: "overlayscreensaver"

    function show(source: string): string { return root.show(source) }
    function hide(source: string): string { return root.hide(source) }
    function toggle(source: string): string { return root.toggle(source) }
    function status(): string { return root.status() }
    function kill(): string { return root.kill() }
  }

  // One overlay surface per monitor.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: overlay
      required property var modelData
      screen: modelData

      visible: root.overlayVisible
      anchors { top: true; bottom: true; left: true; right: true }
      color: "#000000"

      WlrLayershell.namespace: "omarchy-overlay-screensaver"
      WlrLayershell.layer: WlrLayer.Top
      // Grab the keyboard while shown, so Escape reaches us and not the
      // window underneath. No surface exists while hidden, so nothing is
      // grabbed the rest of the time.
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      exclusionMode: ExclusionMode.Ignore

      Image {
        anchors.fill: parent
        source: root.imagePath !== "" ? ("file://" + root.imagePath) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: root.imagePath !== ""
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.hide("click")
      }

      Item {
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: function(event) {
          root.hide("escape")
          event.accepted = true
        }
      }
    }
  }

  Component.onCompleted: refreshImage()
}