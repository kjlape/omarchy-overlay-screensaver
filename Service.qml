import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
// (FileView is in Quickshell core, no extra import needed)

// MVP validation of the overlay-screensaver direction: a layer-shell surface
// on WlrLayer.Top, which Hyprland stacks above ALL toplevels — fullscreen
// windows included, on every workspace — and above the bar. One PanelWindow
// per monitor, driven by a single `visible` flag.
//
// Dismissal (in order of preference):
//   1. Any keystroke — the overlay grabs the keyboard exclusively while shown
//   2. Any click   — MouseArea below
//   3. Mouse move  — Qt-level motion events on the overlay surface itself
//      (see moonshots/standalone-idle-mode.md §4; the old hyprctl poll is gone)
//   4. IPC: `omarchy-overlay-screensaver hide` (works from ssh/TTY)
//   5. Nuke option: `omarchy-shell overlayscreensaver kill` or
//      `omarchy restart shell` — the overlay starts hidden, so a shell
//      restart always recovers the screen. Nothing here runs outside the
//      shell process; there is no daemon that can wedge the overlay.
//
// Config (shell.json plugins[] entry):
//   { "id": "kjlape.overlay-screensaver", "image": "/path/to/img.png",
//     "shader": "starnest" }
// A standalone config file takes LOWER precedence (injected plugins[] entry
// wins): $XDG_CONFIG_HOME/overlay-screensaver/config.json — see
// moonshots/standalone-idle-mode.md §3. Keys: autoShow, idleSeconds, shader,
// image, fps, respectOmarchyStayAwake, autoMode, configOverrides.
// With no `image`, falls back to the current omarchy background.
// `shader` selects the DEFAULT ported xscreensaver GLSL hack (see shaders/)
// used by `showShader`/the `shader` CLI verb when no name is passed; an
// explicit name argument always wins (`shader universeball`).
// `configOverrides` is an optional array of JSON file paths (e.g., 
// "/.local/state/omarchy/current/theme/overlay-screensaver.json"); the
// config files are merged in order, with later files overriding earlier ones
// on a per-key basis.
//
// Autonomous idle mode (opt-in, default OFF): with autoShow enabled and the
// stock omarchy screensaver turned off (`omarchy toggle screensaver`), the
// overlay shows itself after idleSeconds of seat idle via a private
// IdleMonitor (ext-idle-notify-v1). It creates no idle inhibitor, never
// touches DPMS/suspend, never writes the Omarchy stay-awake file (read-only
// consumer) and needs no lock detection — a session lock hides us by protocol
// (moonshots/standalone-idle-mode.md facts 3–5).

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
  property string previousImagePath: "" // outgoing image during a wallpaper crossfade
  readonly property int crossfadeMs: 800

  // ---- autonomous idle mode (moonshots/standalone-idle-mode.md) ----
  // Opt-in auto-activation: everything defaults OFF. The IdleMonitor, the
  // flag files and the stay-awake awareness only ever gate auto-show; manual
  // show/shader IPC works regardless.
  readonly property string configHome: (function () {
    var c = Quickshell.env("XDG_CONFIG_HOME")
    return c !== "" ? c : home + "/.config"
  })()
  readonly property string stateHome: (function () {
    var s = Quickshell.env("XDG_STATE_HOME")
    return s !== "" ? s : home + "/.local/state"
  })()
  readonly property string ownStateDir: stateHome + "/overlay-screensaver"
  readonly property string configPath: configHome + "/overlay-screensaver/config.json"
  readonly property string stayAwakeDir: home + "/.local/state/omarchy/indicators"

  readonly property bool  autoShow: cfg("autoShow", false)
  readonly property int   idleSeconds: Math.max(0, Number(cfg("idleSeconds", 300)))
  readonly property bool  respectStayAwake: cfg("respectOmarchyStayAwake", true)
  property bool togglesLoaded: false     // off/hold flags read at least once
  property bool configProbeRan: false    // own-config existence known
  property bool ownConfigExists: false
  property bool configAdapterLoaded: false // set by the loaded SIGNAL, which
  // fires only after the file is actually parsed — the `loaded` PROPERTY is
  // isLoadedOrAsync and is already true during the async load, which would
  // re-introduce the born-on-300-then-flip race
  property bool offFile: false           // our "never auto-show again" flag
  property bool holdFile: false          // our temporary stay-awake
  property bool stayAwakeLoaded: false   // Omarchy's indicator, read-only
  property bool stayAwake: false
  property bool seenActiveEdge: false    // arming guard — see IdleMonitor below

  // auto-show is opt-in, gated by both flag files and by Omarchy's Stay Awake
  // indicator (awareness, not inhibition — see §2b).
  readonly property bool autoEnabled: autoShow && idleSeconds > 0 && !offFile
    && !holdFile && !(respectStayAwake && stayAwakeLoaded && stayAwake)
  // If auto-activation turns off (disable/hold/Stay Awake), forget the arming
  // guard so a later re-enable on an already-idle seat cannot show the overlay
  // without a fresh observed activity→idle transition.
  // (or a full fresh grace period — see idleGraceTimer).
  onAutoEnabledChanged: if (!autoEnabled) seenActiveEdge = false

  // The IdleMonitor must not exist until config + flag files are loaded:
  // quickshell recreates its underlying ext-idle-notify object when `timeout`
  // changes, and after that recreation the isIdle property stops updating
  // (observed on Quickshell 0.3.1 — events still arrive in C++, the QML
  // property silently dies). Enable/disable flips are safe (they replay
  // current idle state safely; the seenActiveEdge guard absorbs a replayed
  // idle=true). If the config file appears or changes later (idleSeconds
  // edit), rearmIdleMonitor() disables and re-enables the monitor so its
  // timeout is reborn correct, re-arming the guard so an edit made from ssh
  // on an idle seat can't show without a full fresh grace period.
  function recreateIdleMonitor() { root.rearmIdleMonitor() }

  readonly property bool idleConfigSettled: togglesLoaded && configProbeRan
    && (stayAwakeLoaded || !respectStayAwake)
    && (!ownConfigExists || configAdapterLoaded) // never arm before the config's
    // idleSeconds is actually read — a monitor born on the 300s default that
    // later flips to the configured value would hit the timeout-recreation
    // bug and silently die (docs/troubleshooting.md)

  // IdleMonitor lifecycle: statically declared, toggled via `enabled` only.
  // Do NOT create it in a Loader after startup — on Quickshell 0.3.1 a
  // monitor instantiated mid-session (Loader active flip) has a silently
  // dead isIdle property even though it exists and is enabled (verified:
  // a statically-created monitor in the same process fires; the Loader one
  // never does — docs/troubleshooting.md). Enable/disable flips are safe
  // (they replay current idle state; the seenActiveEdge guard + grace timer
  // absorb a replayed idle=true). The timeout binding may only change while the
  // monitor is DISABLED (impl destroyed) — rearmIdleMonitor() enforces the
  // dance for config edits; a timeout change on a live monitor also kills it.
  property bool idleMonitorGate: false // the actual enabled binding
  readonly property bool idleMonitorWanted: autoEnabled && idleConfigSettled
  onIdleMonitorWantedChanged: {
    if (!idleMonitorWanted) {
      seenActiveEdge = false
      idleGraceTimer.stop()
      idleMonitorGate = false
    } else
      idleRearmTimer.restart()
  }
  function rearmIdleMonitor() {
    root.seenActiveEdge = false
    idleGraceTimer.stop()
    idleMonitorGate = false
    idleRearmTimer.restart()
  }
  // give an async config reload a beat before re-enabling, so the frozen
  // timeout below reads the new value at re-enable time
  Timer {
    id: idleRearmTimer
    interval: 150
    running: false
    repeat: false
    onTriggered: root.idleMonitorGate = root.idleMonitorWanted
  }

  // Arming-grace timer (fix for "shell reloaded while the seat is already
  // idle"). The protocol only exposes idle EDGES, not duration, so at arm
  // time we cannot tell "user is away" from "user is right there". Instead of
  // ignoring a replayed idle=true outright (which stranded a restart made
  // while the user was away), we start a full idleSeconds grace period: if no
  // real activity edge arrives before it expires, the user was idle the whole
  // time and we show; any activity cancels it and arms seenActiveEdge
  // normally. The ssh-config-edit protection is intact: there is always a
  // full idleSeconds window between an arm and any show.
  Timer {
    id: idleGraceTimer
    interval: root.idleSeconds * 1000
    running: false
    repeat: false
    onTriggered: {
      // still-armed, still-gated, still-idle, and not somehow already shown
      if (!root.idleMonitorGate || !idleMonitor.isIdle || root.overlayVisible) return
      root.seenActiveEdge = true // act like a normal observed idle edge from here on
      console.log("overlay-screensaver: grace expired on already-idle arm; showing (mode=" + root.configuredAutoMode + ")")
      if (root.configuredAutoMode === "image")
        root.show("idle")
      else
        root.showShader(root.configuredShader, "idle")
    }
  }

  IdleMonitor {
    id: idleMonitor
    enabled: root.idleMonitorGate
    timeout: root.idleSeconds // only mutated while disabled — see above
    respectInhibitors: true // apps' zwp_idle_inhibitor_v1 suppresses us too
    onIsIdleChanged: {
      console.log("overlay-screensaver: idle=" + idleMonitor.isIdle
        + " armed=" + root.seenActiveEdge + " auto=" + root.autoEnabled + " mode=" + root.configuredAutoMode)
      if (!idleMonitor.isIdle) {
        idleGraceTimer.stop() // real activity: grace over, arm normally
        root.seenActiveEdge = true // observed activity; we may auto-show next idle
        return
      }
      if (!root.seenActiveEdge) {
        // Replayed idle at arm time (shell reload / enable flip on an already-
        // idle seat): start the grace timer instead of doing nothing. A user
        // actually present produces an activity edge long before it expires.
        idleGraceTimer.restart()
        return
      }
      if (!root.overlayVisible)
        if (root.configuredAutoMode === "image")
          root.show("idle")
        else
          root.showShader(root.configuredShader, "idle")
    }
  }

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
    "synthwavecity": "shaders/synthwavecity.frag.qsb",
    "downfall": "shaders/downfall.frag.qsb",
    "trizm": "shaders/trizm.frag.qsb",
    "hexplasma": "shaders/hexplasma.frag.qsb",
    "stardome": "shaders/stardome.frag.qsb",
    "rigrekt": "shaders/rigrekt.frag.qsb",
    "xmatrix": "shaders/xmatrix.frag.qsb",
    "xmatrixcrt": "shaders/xmatrixcrt.frag.qsb"
  })
  readonly property int fpsCap: Math.max(1, Number(cfg("fps", 30)))
  readonly property string configuredShader: String(cfg("shader", "starnest")).trim()
  readonly property string configuredAutoMode: String(cfg("autoMode", "shader")).trim()

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

  // Motion-move dismissal state: while shown, the first pointer event after a
  // 250 ms grace sets the baseline; any later ≥1 px move with no button held
  // hides. (Replaced the 300 ms `hyprctl cursorpos` poll — see §4.)
  property point motionBaseline: Qt.point(-1, -1)
  readonly property int motionHideDelayMs: 250

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
    if (v === undefined || v === null) {
      var a = configFile.adapter
      if (a) v = a[name]
    }
    // Check override adapters (last file wins)
    if (v === undefined || v === null) {
      for (var i = root.overrideAdapters.length - 1; i >= 0; i--) {
        var ov = root.overrideAdapters[i]
        if (ov && ov.adapter && ov.adapter.hasOwnProperty(name)) {
          v = ov.adapter[name]
          break
        }
      }
    }
    return (v === undefined || v === null || v === "") ? fallback : v
  }

  // Config image wins; otherwise resolve the current background once on load.
  readonly property string configuredImage: String(cfg("image", "")).trim()

  // All imagePath writes go through here so a wallpaper change mid-show
  // crossfades: the outgoing image stays put underneath while the new one
  // fades in on top (see the Image pair in the PanelWindow).
  function setImage(p) {
    if (p === root.imagePath) return
    root.previousImagePath = root.imagePath
    root.imagePath = p
  }

  function refreshImage() {
    if (root.configuredImage !== "") {
      root.setImage(root.configuredImage)
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
    armMotionDismissal()
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
    armMotionDismissal()
    root.overlayVisible = true
    console.log("overlay-screensaver: shown source=" + String(source || "unknown")
      + " shader=" + root.shaderName)
    return "ok"
  }

  // Reset the motion-dismissal guard for a fresh show: ignore everything for
  // motionHideDelayMs (map-time synthetic motion lands in that window), then
  // sample the baseline from the first real event, then require a ≥1 px move.
  function armMotionDismissal() {
    root.motionBaseline = Qt.point(-1, -1)
    motionGraceTimer.restart()
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
      screens: Quickshell.screens.length,
      // autonomous idle mode state
      autoShow: root.autoShow,
      autoMode: root.configuredAutoMode,
      idleSeconds: root.idleSeconds,
      autoEnabled: root.autoEnabled,
      idle: idleMonitor.isIdle,
      off: root.offFile,
      held: root.holdFile,
      stayAwake: root.stayAwake,
      // diagnostics for the idle path (see docs/troubleshooting.md)
      monitor: idleMonitor.enabled,
      settled: root.idleConfigSettled,
      stayAwakeLoaded: root.stayAwakeLoaded,
      configSeen: root.ownConfigExists,
      configLoaded: root.configAdapterLoaded
    })
  }

  // Drive the shader hack at the configured fps cap while shown. A dedicated
  // clock (not a binding on Date.now()) so the animation restarts cleanly per
  // show; the delta comes from the interval so capping fps stays correct.
  Timer {
    id: shaderTimer
    interval: Math.max(16, Math.round(1000 / root.fpsCap))
    running: root.overlayVisible && root.contentMode === "shader"
    repeat: true
    onTriggered: root.shaderTime += interval / 1000
  }

  Process {
    id: readlinkProc
    command: ["bash", "-c", "readlink -f \"$1\"", "--", root.backgroundLink]
    stdout: StdioCollector {
      onStreamFinished: {
        var p = String(text || "").trim()
        if (p !== "") root.setImage(p)
      }
    }
  }

  // Live-update: omarchy's wallpaper timer repoints the current/background
  // symlink (atomically — a FileView on the link itself can miss that, same
  // gotcha as the config dir watcher below), so watch the parent directory
  // and re-resolve on any change.
  FileView {
    id: backgroundWatcher
    path: String(root.backgroundLink).split("/").slice(0, -1).join("/")
    watchChanges: true
    printErrors: false
    onFileChanged: Qt.callLater(root.refreshImage) // defer past inotify churn
  }

  // Grace window after each show: map delivers synthetic motion/enter under a
  // stationary cursor, which must not self-dismiss the overlay.
  Timer {
    id: motionGraceTimer
    interval: root.motionHideDelayMs
    running: false
    repeat: false
  }

  // ---- autonomous idle mode: flag files + stay-awake awareness ----
  // Our own toggles: off/hold under $XDG_STATE_HOME/overlay-screensaver/
  // (created/removed by the CLI). Omarchy's stay-awake indicator is READ-ONLY
  // — never create, delete, or write it (moonshots/standalone-idle-mode.md §2b,
  // "never write the stay-awake indicator file" invariant).
  Process {
    id: ownStateProbe
    command: ["bash", "-c",
      "d=\"$1\"; mkdir -p \"$d\"; o=no; h=no; " +
      "[ -f \"$d/off\" ] && o=yes; [ -f \"$d/hold\" ] && h=yes; echo \"$o $h\"",
      "--", root.ownStateDir]
    stdout: SplitParser {
      onRead: function (line) {
        var parts = String(line).trim().split(/\s+/)
        root.offFile = parts[0] === "yes"
        root.holdFile = parts[1] === "yes"
        root.togglesLoaded = true
      }
    }
    onExited: ownStateDirWatcher.reload()
  }

  FileView {
    id: ownStateDirWatcher
    path: root.ownStateDir
    watchChanges: true
    printErrors: false
    onFileChanged: if (!ownStateProbe.running) ownStateProbe.running = true
  }

  Process {
    id: stayAwakeProbe
    // Read-only: we do NOT mkdir Omarchy's indicator dir (its own service
    // creates it); printErrors:false tolerates it being absent.
    command: ["bash", "-c",
      "[[ -f \"$1/stay-awake\" ]] && echo yes || echo no", "--", root.stayAwakeDir]
    stdout: SplitParser {
      onRead: function (line) {
        root.stayAwake = String(line).trim() === "yes"
        root.stayAwakeLoaded = true
      }
    }
    onExited: stayAwakeDirWatcher.reload()
  }

  FileView {
    id: stayAwakeDirWatcher
    // Watch the parent directory (upstream's own pattern): a FileView on the
    // file itself would error while absent.
    path: root.stayAwakeDir
    watchChanges: true
    printErrors: false
    onFileChanged: if (!stayAwakeProbe.running) stayAwakeProbe.running = true
  }

  // Own config file: $XDG_CONFIG_HOME/overlay-screensaver/config.json, lower
  // precedence than the injected plugins[] entry (cfg() above). The file may
  // not exist yet (config created after the shell started) — a FileView on an
  // absent file never notices it appear even with watchChanges (verified), so
  // we watch the parent DIRECTORY via a probe and only point configFile at
  // the file once it exists. Any change afterwards recreates the idle monitor
  // (its timeout must never change in place — see troubleshooting.md).
  FileView {
    id: configDirWatcher
    path: root.configHome + "/overlay-screensaver"
    watchChanges: true
    printErrors: false
    onFileChanged: {
      if (!configProbe.running) configProbe.running = true
      if (!reloadTimer.running) reloadTimer.restart()
    }
  }

  // editors often replace the file (new inode), which kills the per-file
  // watch — give the reload a beat, then rebuild the idle monitor so its
  // timeout is born correct (a timeout change in place silently kills it).
  Timer {
    id: configRecreateTimer
    interval: 150
    running: false
    repeat: false
    onTriggered: root.recreateIdleMonitor()
  }

  Process {
    id: configProbe
    command: ["bash", "-c",
      "[[ -f \"$1\" ]] && echo yes || echo no", "--", root.configPath]
    stdout: SplitParser {
      onRead: function (line) {
        var exists = String(line).trim() === "yes"
        if (root.configProbeRan && exists) {
          configFile.reload()
          configRecreateTimer.restart()
        } else if (root.configProbeRan && root.ownConfigExists !== exists) {
          root.recreateIdleMonitor()
        }
        root.ownConfigExists = exists
        root.configProbeRan = true
      }
    }
  }

  FileView {
    id: configFile
    path: root.ownConfigExists ? root.configPath : ""
    watchChanges: true
    printErrors: false
    onLoadFailed: function (error) {
      console.log("overlay-screensaver: own config load failed: " + error)
    }
    onLoaded: root.configAdapterLoaded = true
    adapter: JsonAdapter {
      property bool autoShow: false
      property int idleSeconds: 300
      property int fps: 30
      property bool respectOmarchyStayAwake: true
      property string shader: ""
      property string image: ""
      property string autoMode: "shader"
      // Optional array of JSON config file paths to merge (e.g., theme presets).
      // Each file is a plain object; later files override earlier ones.
      property var configOverrides: []
    }
  }

  // Override config file adapters: loaded from paths in configOverrides
  // Last file wins on a per-key basis.
  property var overrideAdapters: []

  function loadOverrideConfigs() {
    // Clear existing override adapters
    root.overrideAdapters = []
    var overrides = configFile.adapter && configFile.adapter.configOverrides ? configFile.adapter.configOverrides : []
    for (var i = 0; i < overrides.length; i++) {
      var path = String(overrides[i]).trim()
      if (path === "") continue
      // Create FileView for each override config
      var ovFile = Qt.createQmlObject(
        "FileView {\n        path: '" + path + "'\n        watchChanges: true\n        printErrors: false\n        adapter: JsonAdapter {}\n      }",
        root
      )
      // Push loaded adapters to the list after they're loaded
      ovFile.onLoaded = function() {
        root.overrideAdapters.push(ovFile.adapter)
      }
      if (ovFile === null) {
        console.log("overlay-screensaver: failed to load override config " + path)
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

      // Image mode with a crossfade on wallpaper change: the outgoing image
      // sits underneath (kept opaque), the incoming one fades in on top once
      // it has decoded. First show fades up from black; after each fade the
      // outgoing path is dropped so its texture can be freed.
      Item {
        anchors.fill: parent
        visible: root.contentMode === "image" && root.imagePath !== ""

        Image {
          anchors.fill: parent
          source: root.previousImagePath !== "" ? ("file://" + root.previousImagePath) : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          opacity: crossfadeAnim.running ? 0 : 1
        }

        Image {
          id: incomingImage
          anchors.fill: parent
          source: root.imagePath !== "" ? ("file://" + root.imagePath) : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          opacity: 0
          // Reset to 0 on every new source — without this the image keeps
          // opacity 1 from the previous fade and the next crossfade is a
          // hard swap (the fade has nothing left to animate).
          onSourceChanged: opacity = 0
          onStatusChanged: if (status === Image.Ready) opacity = 1
          Behavior on opacity {
            NumberAnimation {
              id: crossfadeAnim
              duration: root.crossfadeMs
              onStopped: root.previousImagePath = ""
            }
          }
        }
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
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        // §4b: blank the cursor while shown; unmap restores it by itself —
        // leak-proof by construction (never use `cursor:invisible`).
        cursorShape: root.overlayVisible ? Qt.BlankCursor : Qt.ArrowCursor
        onClicked: root.hide("click")
        onPositionChanged: function (mouse) {
          if (!root.overlayVisible || mouse.buttons !== Qt.NoButton) return
          if (motionGraceTimer.running) return // map-time synthetic motion
          if (root.motionBaseline.x < 0) {
            root.motionBaseline = Qt.point(mouse.x, mouse.y)
            return
          }
          if (Math.abs(mouse.x - root.motionBaseline.x) >= 1
              || Math.abs(mouse.y - root.motionBaseline.y) >= 1)
            root.hide("motion")
        }
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

  Component.onCompleted: {
    loadOverrideConfigs()
    refreshImage()
    ownStateProbe.running = true
    stayAwakeProbe.running = true
    configProbe.running = true
  }

  Timer {
    id: reloadTimer
    interval: 150
    running: false
    repeat: false
    onTriggered: loadOverrideConfigs()
  }
}