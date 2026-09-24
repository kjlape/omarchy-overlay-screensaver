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
//   1. Any keystroke — the overlay grabs the keyboard exclusively while shown
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
//   { "id": "kjlape.overlay-screensaver", "image": "/path/to/img.png",
//     "shader": "starnest" }
// With no `image`, falls back to the current omarchy background.
// `shader` selects the DEFAULT ported xscreensaver GLSL hack (see shaders/)
// used by `showShader`/the `shader` CLI verb when no name is passed; an
// explicit name argument always wins (`shader universeball`).

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

  // ---- shader hack content (see moonshots/xscreensaver-hacks.md) ----
  // "image" = static image / background (the MVP); "shader" = a ported
  // xscreensaver GLSL hack rendered by a ShaderEffect inside the same
  // layer-shell surface. Everything stays in-process, so the recovery
  // guarantee is untouched (no Xvfb / child-process tree needed).
  property string contentMode: "image"
  property string shaderName: ""   // resolved shader id, "" = none available
  property real shaderTime: 0      // seconds of shader animation so far

  // Ported hacks, keyed by name → qsb (baked with qt6-shadertools `qsb`).
  // Each frag pairs with <name>.vert.qsb. The ShaderEffect binds these
  // paths dynamically from `shaderName`, so adding an entry here (plus the
  // four shader files) is all a new port needs — see docs/roadmap.md.
  readonly property var knownShaders: ({
    "starnest": "shaders/starnest.frag.qsb",
    "universeball": "shaders/universeball.frag.qsb",
    "topologica": "shaders/topologica.frag.qsb",
    "synthwavecity": "shaders/synthwavecity.frag.qsb"
  })
  readonly property string configuredShader: String(cfg("shader", "starnest")).trim()

  // Active shader's baked stages, as URLs for the ShaderEffect. While no
  // shader is active (image mode, before the first `showShader`) they fall
  // back to the first known shader's files — the effect is hidden in image
  // mode anyway, and a ShaderEffect with an empty fragmentShader fails to
  // load, so a placeholder keeps the component valid at all times.
  readonly property url activeFragUrl: root.knownShaders[root.shaderName] !== undefined
    ? Qt.resolvedUrl(root.knownShaders[root.shaderName])
    : Qt.resolvedUrl(root.knownShaders[Object.keys(root.knownShaders)[0]])
  readonly property url activeVertUrl: Qt.resolvedUrl(
    root.activeFragUrl.toString().replace(/\.frag\.qsb$/, ".vert.qsb"))

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

  // Map a requested shader name to a known one. Empty/missing request falls
  // back to the configured default; an unknown name logs and returns "".
  function resolveShaderName(requested): string {
    var wanted = String(requested || "").trim()
    if (wanted === "") wanted = root.configuredShader
    if (root.knownShaders[wanted] === undefined) {
      console.log("overlay-screensaver: unknown shader \"" + wanted
        + "\" (known: " + Object.keys(root.knownShaders).join(", ") + ")")
      return ""
    }
    return wanted
  }

  function show(source): string {
    root.contentMode = "image"
    refreshImage()
    root.cursorBaseline = "" // resample cursor position on each show
    root.overlayVisible = true
    console.log("overlay-screensaver: shown source=" + String(source || "unknown")
      + " image=" + (root.imagePath || "(none)"))
    return "ok"
  }

  // Show a shader hack instead of the static image. `shader` names a
  // knownShaders entry; empty falls back to the configured default.
  // Falls back to the image mode (with an error string) if the name is
  // unknown — never leaves the overlay shown in a broken state.
  function showShader(shader, source): string {
    var name = root.resolveShaderName(shader)
    if (name === "") return "unknown shader: \"" + String(shader || "").trim()
      + "\" (known: " + Object.keys(root.knownShaders).join(", ") + ")"
    root.shaderName = name
    root.contentMode = "shader"
    root.shaderTime = 0 // restart animation on each show
    root.cursorBaseline = "" // resample cursor position on each show
    root.overlayVisible = true
    console.log("overlay-screensaver: shown source=" + String(source || "unknown")
      + " shader=" + root.shaderName)
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

  function shaders(): string {
    return Object.keys(root.knownShaders).join("\n")
  }

  function status(): string {
    return JSON.stringify({
      visible: root.overlayVisible,
      mode: root.contentMode,
      shader: root.shaderName,
      shaders: Object.keys(root.knownShaders),
      image: root.imagePath,
      screens: Quickshell.screens.length
    })
  }

  // Drive the shader hack at ~60 fps while it is shown. A dedicated clock
  // (not a binding on Date.now()) so the animation restarts cleanly per show.
  Timer {
    id: shaderTimer
    interval: 16
    running: root.overlayVisible && root.contentMode === "shader"
    repeat: true
    onTriggered: root.shaderTime += 0.016
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
    function showShader(shader: string, source: string): string { return root.showShader(shader, source) }
    function shaders(): string { return root.shaders() }
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
        visible: root.contentMode === "image" && root.imagePath !== ""
      }

      // Ported xscreensaver GLSL hack, rendered in-process on the same
      // layer-shell surface. Uniforms `time`/`aspect` map to the properties
      // below; the shader stages are baked to shaders/<name>.{frag,vert}.qsb
      // with qt6-shadertools, selected by name via `activeFragUrl`/
      // `activeVertUrl` (the vertex stage is always the same passthrough —
      // see shaders/starnest.vert — but Qt reloads both when either binding
      // changes, which is what swaps shaders live).
      ShaderEffect {
        anchors.fill: parent
        visible: root.contentMode === "shader"
        fragmentShader: root.activeFragUrl
        vertexShader: root.activeVertUrl // Qt's default vertex stage lacks an explicit-location output the NVIDIA linker will accept
        blending: false
        // property names must match the uniform names in the .frag exactly
        property real time: root.shaderTime
        property real aspect: width / height
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.hide("click")
      }

      Item {
        anchors.fill: parent
        focus: true

        // Dismiss on any keystroke (Escape included).
        Keys.onPressed: function(event) {
          root.hide("key-" + event.text)
          event.accepted = true
        }
      }
    }
  }

  Component.onCompleted: refreshImage()
}