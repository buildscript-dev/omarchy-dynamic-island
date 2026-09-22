import QtQuick

// Round glyph button with the iOS press feel: a soft highlight on hover and
// a springy squeeze on press.
Item {
  id: root

  property string glyph: ""
  property string glyphFont: ""
  property int glyphSize: 18
  property color color: "white"
  property color hoverFill: Qt.rgba(1, 1, 1, 0.1)
  property bool enabledState: true
  signal clicked()

  implicitWidth: glyphSize + 16
  implicitHeight: glyphSize + 16
  opacity: enabledState ? 1 : 0.35

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: root.hoverFill
    opacity: mouse.containsMouse && root.enabledState ? 1 : 0
    scale: mouse.containsMouse ? 1 : 0.7
    Behavior on opacity { NumberAnimation { duration: 140 } }
    Behavior on scale { SpringAnimation { spring: 5; damping: 0.4 } }
  }

  Text {
    textFormat: Text.PlainText
    anchors.centerIn: parent
    text: root.glyph
    font.family: root.glyphFont
    font.pixelSize: root.glyphSize
    color: root.color
    scale: mouse.pressed ? 0.82 : 1
    Behavior on scale { SpringAnimation { spring: 6; damping: 0.3; epsilon: 0.01 } }
    Behavior on color { ColorAnimation { duration: 200 } }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    enabled: root.enabledState
    onClicked: root.clicked()
  }
}
