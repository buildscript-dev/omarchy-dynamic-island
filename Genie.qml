import QtQuick
import Quickshell
import Quickshell.Wayland

// The minimise / restore flight: a window cut into thin horizontal strips that
// are pulled into (or pushed out of) the island, the nearest strips first, so
// the window narrows into a funnel, like Compiz's Magic Lamp and macOS's Genie.
// Pure QML: no shader, so it needs no compiled .qsb and nothing from the GPU
// beyond texture sampling. It lives only while it plays.
//
// p = 0: the window exactly where it was. p = 1: swallowed by the island.
PanelWindow {
  id: g

  // The live window (a Hyprland toplevel with a capture handle), or a frozen
  // picture of it (snap) when the window is already out of sight.
  property var toplevel: null
  property string snap: ""
  // Window rectangle and the island's centre, in this screen's pixels.
  property rect from: Qt.rect(0, 0, 100, 100)
  property point to: Qt.point(0, 0)
  property real p: 0
  property real startP: 0
  Component.onCompleted: p = startP
  // Once the real window is hidden its capture goes black, so the caller freezes
  // the last good picture first (freeze(url)) and the strips read from that.
  property string frozen: ""
  function freeze(url) { frozen = url }
  readonly property bool live: toplevel !== null && snap === "" && frozen === ""
  readonly property bool hasContent: live ? cap.hasContent : snapImg.status === Image.Ready
  // Funnel: how much later the far end of the window lets go than the near end.
  readonly property real lag: 0.55

  signal finished(bool swallowed)

  // Visible from the start: it only captures while it is on screen. Until the
  // first frame arrives the strips draw nothing, so the real window shows through.
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  mask: Region {}
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "omarchy-dynamic-island-genie"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  // A picture of the window as it is now; the caller keeps the result alive and
  // hands result.url back as `snap` to restore it later.
  function grab(done) { src.grabToImage(done) }

  function play(target, ms) {
    anim.stop()
    anim.to = target
    anim.duration = ms
    anim.start()
  }

  NumberAnimation {
    id: anim
    target: g
    property: "p"
    easing.type: Easing.InOutCubic
    onFinished: g.finished(g.p > 0.5)
  }

  // The source: drawn only into the texture, never on screen itself.
  Item {
    id: src
    x: g.from.x
    y: g.from.y
    width: g.from.width
    height: g.from.height

    ScreencopyView {
      id: cap
      anchors.fill: parent
      visible: g.live
      captureSource: g.live ? g.toplevel.wayland : null
      live: g.live
      paintCursor: false
    }
    Image {
      id: snapImg
      anchors.fill: parent
      visible: !g.live
      source: g.frozen !== "" ? g.frozen : g.snap
      cache: false
      smooth: true
    }
  }

  // One mesh, warped by shaders/genie.vert: smooth edges, no strips. The shaders
  // are built with qsb from the .vert / .frag next to the .qsb files.
  ShaderEffectSource {
    id: tex
    sourceItem: src
    hideSource: true
    live: g.live
    smooth: true
    visible: false
  }
  ShaderEffect {
    id: fx
    x: g.from.x
    y: g.from.y
    width: g.from.width
    height: g.from.height
    mesh: GridMesh { resolution: Qt.size(2, 72) }
    property variant source: tex
    property real p: g.p
    property real lag: g.lag
    property real winW: g.from.width
    property real winH: g.from.height
    property real tx: g.to.x
    property real ty: g.to.y
    property real cx0: g.from.x + g.from.width / 2
    property real y0: g.from.y
    property real narrow: 12 / Math.max(1, g.from.width)
    property real ox: g.from.x
    property real oy: g.from.y
    vertexShader: Qt.resolvedUrl("shaders/genie.vert.qsb")
    fragmentShader: Qt.resolvedUrl("shaders/genie.frag.qsb")
    visible: g.hasContent && g.p < 0.995
    // The last bit of the way, it melts into the island.
    opacity: g.p > 0.92 ? Math.max(0, (1 - g.p) / 0.08) : 1
  }
}
