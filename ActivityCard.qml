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

  // Black card, one accent: the read-out, the tick bar and the primary button take it.
  readonly property color accent: s.tint(info.tint)
  // 0..1 across the tick bar: what is left of a timer, otherwise the second hand of a minute.
  readonly property real progress: {
    s.now
    if (kind === "timer") return s.timerTotal > 0 ? Math.max(0, Math.min(1, s.timerLeft / s.timerTotal)) : 0
    var secs = kind === "stopwatch" ? s.stopwatchElapsed
      : kind === "recording" ? (s.recordingSince > 0 ? (Date.now() - s.recordingSince) / 1000 : 0)
      : kind === "phone" ? (s.phoneSince > 0 ? (Date.now() - s.phoneSince) / 1000 : 0) : 0
    return (secs % 60) / 60
  }
  readonly property bool tickBar: kind !== "ai"

  Row {
    id: head
    x: 22
    y: 18
    spacing: 7
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 8; height: 8; radius: 4
      color: root.accent
    }
    Text {
      text: root.info.title
      font.family: root.s.textFont
      font.pixelSize: Model.TYPE.footnote
      font.weight: Font.DemiBold
      color: root.accent
      textFormat: Text.PlainText
    }
  }
  Text {
    anchors.right: parent.right
    anchors.rightMargin: 24
    anchors.verticalCenter: head.verticalCenter
    width: parent.width / 2
    horizontalAlignment: Text.AlignRight
    text: root.info.sub
    font.family: root.s.textFont
    font.pixelSize: Model.TYPE.footnote
    color: root.dim
    elide: Text.ElideRight
    textFormat: Text.PlainText
  }

  Text {
    id: value
    anchors.left: parent.left
    anchors.leftMargin: 22
    anchors.top: head.bottom
    anchors.topMargin: 2
    text: root.info.value !== "" ? root.info.value : root.info.sub
    font.family: root.s.textFont
    font.pixelSize: root.info.value !== "" ? 40 : 22
    font.weight: Font.Bold
    font.features: { "tnum": 1 }
    color: root.accent
    textFormat: Text.PlainText
  }

  // Tick bar, like the reference's Voice Memo / charging cards.
  Row {
    id: ticks
    visible: root.tickBar
    anchors.left: parent.left
    anchors.leftMargin: 22
    anchors.right: parent.right
    anchors.rightMargin: 22
    anchors.top: value.bottom
    anchors.topMargin: 6
    height: 12
    spacing: 3
    Repeater {
      model: 36
      delegate: Rectangle {
        required property int index
        width: (ticks.width - 35 * 3) / 36
        height: parent.height
        radius: width / 2
        color: (index + 1) / 36 <= root.progress + 0.001 ? root.accent : Qt.rgba(1, 1, 1, 0.16)
      }
    }
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 14
    spacing: 10
    Repeater {
      model: root.info.buttons
      delegate: Rectangle {
        required property var modelData
        required property int index
        readonly property color tone: modelData.red ? root.s.tint("red") : root.accent
        readonly property bool primary: index === 0 && !modelData.red
        width: 96
        height: 36
        radius: 18
        color: primary ? Qt.rgba(tone.r, tone.g, tone.b, btn.containsMouse ? 1 : 0.92)
          : Qt.rgba(tone.r, tone.g, tone.b, btn.containsMouse ? 0.34 : 0.22)
        Row {
          anchors.centerIn: parent
          spacing: 7
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.glyph
            font.family: modelData.text ? root.s.textFont : root.s.iconFont
            font.pixelSize: modelData.text ? 14 : 16
            font.weight: Font.DemiBold
            color: primary ? "black" : tone
            textFormat: Text.PlainText
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            font.family: root.s.textFont
            font.pixelSize: Model.TYPE.subhead
            font.weight: Font.DemiBold
            color: primary ? "black" : tone
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
