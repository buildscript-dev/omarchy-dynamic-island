import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// The picture of a window you are dragging toward the island. Hyprland's own drag
// keeps the window's corner at a fixed distance from the pointer, so a window that
// shrinks drifts off to one side; this copy stays centred under the pointer instead.
// A frozen snapshot is taken first (the real window then shrinks to a speck), so the
// picture keeps the window's full-size contents however small it is drawn.
PanelWindow {
  id: g

  property var toplevel: null        // the dragged window's capture handle
  property real srcW: 100            // its size before the drag shrank it
  property real srcH: 100
  property string frozen: ""         // set by the caller once the snapshot exists
  // Centre and size of the copy, in this screen's pixels.
  property real cx: 0
  property real cy: 0
  property real w: 100
  property real h: 100
  // 1 shown, 0 gone: the caller fades it when the window is let go somewhere else.
  property real fade: 1
  property bool grabbing: false
  readonly property bool hasContent: cap.hasContent

  function grab(done) { src.grabToImage(done) }

  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  mask: Region {}
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "omarchy-dynamic-island-ghost"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  // The live source, drawn only into a texture; it stops once the snapshot is taken.
  Item {
    id: src
    width: g.srcW
    height: g.srcH
    ScreencopyView {
      id: cap
      anchors.fill: parent
      captureSource: g.frozen === "" && g.toplevel ? g.toplevel.wayland : null
      live: g.frozen === ""
      paintCursor: false
    }
  }
  ShaderEffectSource { sourceItem: src; hideSource: true; live: g.frozen === ""; visible: false }

  Item {
    id: card
    visible: g.frozen !== "" && g.fade > 0.01
    width: Math.max(2, g.w)
    height: Math.max(2, g.h)
    x: g.cx - width / 2
    y: g.cy - height / 2
    opacity: g.fade
    layer.enabled: true
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: Qt.rgba(0, 0, 0, 0.55)
      shadowBlur: 0.9
      shadowVerticalOffset: 6
      autoPaddingEnabled: true
    }

    Item {
      id: face
      anchors.fill: parent
      layer.enabled: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: roundMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }
      Image {
        anchors.fill: parent
        source: g.frozen
        cache: false
        smooth: true
        fillMode: Image.Stretch
      }
    }
    Rectangle {
      id: roundMask
      anchors.fill: parent
      radius: Math.min(16, Math.min(width, height) / 3)
      color: "white"
      layer.enabled: true
      visible: false
    }
  }
}
