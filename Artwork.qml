import QtQuick
import QtQuick.Effects

// Rounded album art (or any image) with a glyph fallback.
Item {
  id: root

  property string source: ""
  property real radius: 6
  property string fallbackGlyph: ""
  property string glyphFont: ""
  property color fallbackColor: Qt.rgba(1, 1, 1, 0.12)
  property color glyphColor: "white"

  readonly property bool ready: image.status === Image.Ready

  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: root.fallbackColor
    visible: !root.ready

    Text {
      anchors.centerIn: parent
      text: root.fallbackGlyph
      font.family: root.glyphFont
      font.pixelSize: Math.round(root.height * 0.5)
      color: root.glyphColor
      opacity: 0.8
    }
  }

  Image {
    id: image
    anchors.fill: parent
    source: root.source
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
    smooth: true
    mipmap: true
    sourceSize: Qt.size(Math.max(64, root.width * 2), Math.max(64, root.height * 2))
    visible: false
  }

  Item {
    id: mask
    anchors.fill: parent
    layer.enabled: true
    visible: false
    Rectangle {
      anchors.fill: parent
      radius: root.radius
      color: "black"
    }
  }

  MultiEffect {
    anchors.fill: parent
    source: image
    maskEnabled: true
    maskSource: mask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1.0
    visible: root.ready
    opacity: root.ready ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 250 } }
  }
}
