import QtQuick
import QtQuick.Window

// Offline render check for a ported shader hack: loads shaders/<name>.{frag,
// vert}.qsb into a ShaderEffect, grabs a frame at each of a few animation
// times, writes PNGs, exits. Renders without covering the screen, so a port
// can be eyeballed (orientation, skew, density, glyph legibility) before the
// live overlay test — and re-rendered at any size without restarting the
// shell.
//
//   QT_QUICK_BACKEND=opengl QT_QPA_PLATFORM=offscreen \
//     /usr/lib/qt6/bin/qml tools/shadercheck.qml <name> [width height [t1,t2,...]]
//
// writes /tmp/shadercheck-<name>-<n>.png. The offscreen platform needs the
// OpenGL backend explicitly: with Qt's default (rhi → software here) a
// ShaderEffect silently renders nothing, which looks exactly like a broken
// port. Times default to [1, 3, 7, 12] s. Add QT_LOGGING_RULES=qml.debug=true
// to get the "wrote <path>" console lines back (Qt 6 disables that category).
// The .qsb paths resolve relative to this file (tools/../shaders), so the
// working directory doesn't matter.
Window {
  id: win
  visible: true
  property var argv: Qt.application.arguments || []
  width: Number(argv[3] || 1280)
  height: Number(argv[4] || 800)
  color: "black"
  property string shader: String(argv[2] || "starnest")
  property real t: 0
  property int shot: 0
  property var times: String(argv[5] || "1,3,7,12").split(",").map(Number)

  ShaderEffect {
    id: fx
    anchors.fill: parent
    blending: false
    fragmentShader: Qt.resolvedUrl("../shaders/" + win.shader + ".frag.qsb")
    vertexShader: Qt.resolvedUrl("../shaders/" + win.shader + ".vert.qsb")
    property real time: win.t
    property real aspect: width / height
  }

  function grab() {
    win.t = win.times[win.shot]
    later.restart()
  }

  Timer {
    id: later
    interval: 150
    onTriggered: fx.grabToImage(function (r) {
      var path = "/tmp/shadercheck-" + win.shader + "-" + win.shot + ".png"
      console.log((r.saveToFile(path) ? "wrote " : "SAVE FAILED ") + path
        + "  t=" + win.t + " " + win.width + "x" + win.height)
      win.shot++
      if (win.shot < win.times.length) win.grab()
      else Qt.exit(0)
    })
  }

  Component.onCompleted: win.grab()
}
