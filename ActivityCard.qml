import QtQuick
import "IslandModel.js" as Model

// A running activity at full size, one page of the opened island: what it
// is, its big read-out, and the controls you'd reach for. Music has its own
// page (ExpandedView) and a call has CallView; this covers the rest.
Item {
  id: root

  property var s: null
  property string kind: ""

  readonly property color fg: s.textColor
  readonly property color dim: s.secondaryText

  readonly property var info: {
    s.now
    if (kind === "timer")
      return { glyph: s.glyphs.timer, tint: "orange", title: "Timer",
        value: Model.formatTime(s.timerLeft), sub: s.timerPausedLeft >= 0 ? "Paused" : "of " + Model.formatTime(s.timerTotal),
        buttons: [
          { id: "pause", glyph: s.timerPausedLeft >= 0 ? s.glyphs.play : s.glyphs.pause, label: s.timerPausedLeft >= 0 ? "Resume" : "Pause" },
          { id: "plus", glyph: "+1", label: "1 min", text: true },
          { id: "stop", glyph: "", label: "Cancel", red: true }] }
    if (kind === "stopwatch")
      return { glyph: s.glyphs.stopwatch, tint: "orange", title: "Stopwatch",
        value: Model.formatTime(s.stopwatchElapsed), sub: s.stopwatchHeld >= 0 ? "Paused" : "Running",
        buttons: [
          { id: "pause", glyph: s.stopwatchHeld >= 0 ? s.glyphs.play : s.glyphs.pause, label: s.stopwatchHeld >= 0 ? "Resume" : "Pause" },
          { id: "stop", glyph: "", label: "Reset", red: true }] }
    if (kind === "recording")
      return { glyph: s.glyphs.record, tint: "red", title: "Screen Recording",
        value: s.recordingSince > 0 ? Model.formatTime((Date.now() - s.recordingSince) / 1000) : "", sub: "Recording",
        buttons: [{ id: "stop", glyph: "", label: "Stop", red: true }] }
    if (kind === "phone")
      return { glyph: "", tint: "green", title: s.phoneName, value: s.phoneSince > 0 ? Model.formatTime((Date.now() - s.phoneSince) / 1000) : "",
        sub: "Mirroring on this PC", buttons: [{ id: "stop", glyph: "", label: "Stop", red: true }] }
    if (kind === "ai")
      return { glyph: s.glyphs.robot, tint: "blue", title: "Assistant", value: "", sub: s.aiText || "Working on your phone", buttons: [] }
    return { glyph: "", tint: "white", title: "", value: "", sub: "", buttons: [] }
  }

  function act(id) {
    if (kind === "timer") {
      if (id === "pause") s.toggleTimerPause()
      else if (id === "plus") s.addTimer(60)
      else if (id === "stop") s.cancelTimer()
    } else if (kind === "stopwatch") {
      if (id === "pause") s.toggleStopwatch()
      else if (id === "stop") s.resetStopwatch()
    } else if (kind === "recording") {
      if (id === "stop") s.stopRecording()
    } else if (kind === "phone") {
      if (id === "stop" && s.phone) s.phone.stopControl()
    }
  }

  Rectangle {
    id: badge
    x: 22
    y: 22
    width: 52
    height: 52
    radius: 26
    color: Qt.rgba(1, 1, 1, 0.12)
    Text {
      anchors.centerIn: parent
      text: root.info.glyph
      font.family: root.s.iconFont
      font.pixelSize: 24
      color: root.s.tint(root.info.tint)
      textFormat: Text.PlainText
    }
  }
  Column {
    anchors.left: badge.right
    anchors.leftMargin: 14
    anchors.right: value.left
    anchors.rightMargin: 12
    anchors.verticalCenter: badge.verticalCenter
    spacing: 2
    Text {
      width: parent.width
      text: root.info.title
      font.family: root.s.textFont
      font.pixelSize: 17
      font.weight: Font.DemiBold
      color: root.fg
      elide: Text.ElideRight
      textFormat: Text.PlainText
    }
    Text {
      width: parent.width
      text: root.info.sub
      font.family: root.s.textFont
      font.pixelSize: 12
      color: root.dim
      elide: Text.ElideRight
      textFormat: Text.PlainText
    }
  }
  Text {
    id: value
    anchors.right: parent.right
    anchors.rightMargin: 24
    anchors.verticalCenter: badge.verticalCenter
    text: root.info.value
    font.family: root.s.textFont
    font.pixelSize: 34
    font.weight: Font.Light
    font.features: { "tnum": 1 }
    color: root.s.tint(root.info.tint)
    textFormat: Text.PlainText
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 18
    spacing: 16
    Repeater {
      model: root.info.buttons
      delegate: Rectangle {
        required property var modelData
        width: 104
        height: 40
        radius: 20
        color: modelData.red ? Qt.rgba(1, 0.27, 0.23, btn.containsMouse ? 0.34 : 0.24)
          : btn.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.14)
        Row {
          anchors.centerIn: parent
          spacing: 8
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.glyph
            font.family: modelData.text ? root.s.textFont : root.s.iconFont
            font.pixelSize: modelData.text ? 14 : 16
            font.weight: Font.DemiBold
            color: modelData.red ? root.s.tint("red") : root.fg
            textFormat: Text.PlainText
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            font.family: root.s.textFont
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: modelData.red ? root.s.tint("red") : root.fg
            textFormat: Text.PlainText
          }
        }
        MouseArea {
          id: btn
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.act(modelData.id)
        }
      }
    }
  }
}
