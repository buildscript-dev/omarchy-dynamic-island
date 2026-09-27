import QtQuick
import Quickshell.Services.Pipewire

// The ongoing call, opened by clicking the call pill: who it is, how long,
// and four buttons — mute, sound output, notes (i), end. Notes turns the
// view into a small form (name, number, time, purpose, notes) saved as a
// Markdown file under ~/.local/share/omarchy/call-notes/.
Item {
  id: root

  property var s: null
  property bool active: false
  property bool notesOpen: false
  signal closeRequested()

  readonly property var call: s.currentCall
  readonly property var phone: s.phone
  readonly property color fg: s.textColor
  readonly property color dim: s.secondaryText
  readonly property color fieldFill: Qt.rgba(fg.r, fg.g, fg.b, 0.08)

  readonly property int preferredWidth: notesOpen ? 380 : 340
  readonly property int preferredHeight: notesOpen ? notes.implicitHeight + 28 : 152

  // The note keeps who and when from the moment it was opened, so it can be
  // finished after the call has ended.
  property var noteCall: ({})
  property real noteTime: 0
  function openNotes() {
    var c = call || {}
    noteCall = { name: String(c.name || ""), number: String(c.number || ""), activeSince: Number(c.activeSince) || 0 }
    noteTime = noteCall.activeSince > 0 ? noteCall.activeSince * 1000 : Date.now()
    nameField.text = noteCall.name
    numberField.text = noteCall.number
    purposeField.text = ""
    notesField.text = ""
    notesOpen = true
    Qt.callLater(function() { purposeField.input.forceActiveFocus() })
  }
  function saveNotes() {
    s.saveCallNote({ name: nameField.text, number: numberField.text, time: noteTime,
      duration: noteCall.activeSince > 0 ? Date.now() / 1000 - noteCall.activeSince : 0,
      purpose: purposeField.text, notes: notesField.text })
    notesOpen = false
    if (!call) closeRequested()
  }
  function cancelNotes() {
    notesOpen = false
    if (!call) closeRequested()
  }
  onCallChanged: if (!call && !notesOpen) closeRequested()
  onActiveChanged: if (!active) notesOpen = false

  // Sound output: step through the PC's outputs (speakers, headphones, buds).
  readonly property var sinks: {
    var out = []
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream && n.audio) out.push(n)
    }
    return out
  }
  readonly property var sink: Pipewire.defaultAudioSink
  function sinkName(n) { return n ? String(n.description || n.nickname || n.name || "Output") : "Output" }
  function nextSink() {
    if (sinks.length < 2) return
    var i = sinks.indexOf(sink)
    Pipewire.preferredDefaultAudioSink = sinks[(i + 1) % sinks.length]
  }

  Keys.onEscapePressed: if (notesOpen) cancelNotes(); else closeRequested()

  // ------------------------------------------------ call
  Item {
    anchors.fill: parent
    visible: !root.notesOpen

    Rectangle {
      id: avatar
      x: 18
      y: 18
      width: 44
      height: 44
      radius: 22
      color: Qt.rgba(1, 1, 1, 0.16)
      Text {
        anchors.centerIn: parent
        text: root.call && root.call.name ? root.call.name.charAt(0).toUpperCase() : "?"
        font.family: root.s.textFont
        font.pixelSize: 19
        font.weight: Font.DemiBold
        color: root.fg
        textFormat: Text.PlainText
      }
    }
    Column {
      anchors.left: avatar.right
      anchors.leftMargin: 12
      anchors.right: parent.right
      anchors.rightMargin: 18
      anchors.verticalCenter: avatar.verticalCenter
      spacing: 2
      Text {
        width: parent.width
        text: root.s.callTitle(root.call)
        font.family: root.s.textFont
        font.pixelSize: 16
        font.weight: Font.DemiBold
        color: root.fg
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
      Text {
        width: parent.width
        text: root.call ? ((root.call.name && root.call.number ? root.call.number + "  ·  " : "") + root.s.callElapsed(root.call)) : "Call ended"
        font.family: root.s.textFont
        font.pixelSize: 12
        color: root.s.tint("green")
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 80
      spacing: 18
      Repeater {
        model: [
          { act: "mute", glyph: root.phone && root.phone.micMuted ? "" : "", label: root.phone && root.phone.micMuted ? "Unmute" : "Mute",
            on: !!(root.phone && root.phone.micMuted), color: "white" },
          { act: "sound", glyph: "", label: root.sinkName(root.sink), on: false, color: "white" },
          { act: "notes", glyph: "", label: "Notes", on: false, color: "white" },
          { act: "end", glyph: "", label: "End", on: true, color: "red" }
        ]
        delegate: Column {
          required property var modelData
          spacing: 4
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 46
            height: 46
            radius: 23
            color: modelData.color === "red" ? root.s.tint("red")
              : modelData.on ? Qt.rgba(1, 1, 1, 0.9)
              : btnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.16)
            Text {
              anchors.centerIn: parent
              text: modelData.glyph
              font.family: root.s.iconFont
              font.pixelSize: 20
              color: modelData.on && modelData.color !== "red" ? "black" : "white"
              textFormat: Text.PlainText
            }
            MouseArea {
              id: btnMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                var a = modelData.act
                if (a === "mute" && root.phone) root.phone.toggleMute()
                else if (a === "sound") root.nextSink()
                else if (a === "notes") root.openNotes()
                else if (a === "end" && root.phone) root.phone.hangup(root.call ? String(root.call.path || "") : "")
              }
            }
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 64
            horizontalAlignment: Text.AlignHCenter
            text: modelData.label
            font.family: root.s.textFont
            font.pixelSize: 10
            color: root.dim
            elide: Text.ElideRight
            textFormat: Text.PlainText
          }
        }
      }
    }
  }

  // ------------------------------------------------ notes
  component Field: Rectangle {
    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    width: parent.width
    height: 34
    radius: 10
    color: root.fieldFill
    border.width: input.activeFocus ? 1 : 0
    border.color: Qt.rgba(1, 1, 1, 0.3)
    TextInput {
      id: input
      anchors.fill: parent
      anchors.leftMargin: 12
      anchors.rightMargin: 12
      verticalAlignment: TextInput.AlignVCenter
      font.family: root.s.textFont
      font.pixelSize: 13
      color: root.fg
      selectByMouse: true
      clip: true
      maximumLength: 300
      activeFocusOnTab: true
      Text {
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        visible: input.text === "" && !input.activeFocus
        text: parent.parent.placeholder
        font: input.font
        color: root.dim
        textFormat: Text.PlainText
      }
    }
  }

  Column {
    id: notes
    visible: root.notesOpen
    x: 16
    y: 14
    width: parent.width - 32
    spacing: 8

    Row {
      width: parent.width
      Text {
        width: parent.width - timeLabel.width
        text: "Call Notes"
        font.family: root.s.textFont
        font.pixelSize: 16
        font.weight: Font.Bold
        color: root.fg
        textFormat: Text.PlainText
      }
      Text {
        id: timeLabel
        anchors.verticalCenter: parent.verticalCenter
        text: root.noteTime > 0 ? Qt.formatDateTime(new Date(root.noteTime), "d MMM, HH:mm") : ""
        font.family: root.s.textFont
        font.pixelSize: 12
        color: root.dim
        textFormat: Text.PlainText
      }
    }
    Row {
      width: parent.width
      spacing: 8
      Field { id: nameField; width: (parent.width - 8) / 2; placeholder: "Name" }
      Field { id: numberField; width: (parent.width - 8) / 2; placeholder: "Number" }
    }
    Field { id: purposeField; placeholder: "Purpose" }
    Rectangle {
      width: parent.width
      height: 110
      radius: 10
      color: root.fieldFill
      border.width: notesField.activeFocus ? 1 : 0
      border.color: Qt.rgba(1, 1, 1, 0.3)
      Flickable {
        id: notesFlick
        anchors.fill: parent
        anchors.margins: 10
        contentHeight: notesField.implicitHeight
        clip: true
        TextEdit {
          id: notesField
          width: notesFlick.width
          font.family: root.s.textFont
          font.pixelSize: 13
          color: root.fg
          wrapMode: TextEdit.Wrap
          selectByMouse: true
          textFormat: TextEdit.PlainText
          activeFocusOnTab: true
          onCursorRectangleChanged: {
            if (cursorRectangle.y < notesFlick.contentY) notesFlick.contentY = cursorRectangle.y
            else if (cursorRectangle.y + cursorRectangle.height > notesFlick.contentY + notesFlick.height)
              notesFlick.contentY = cursorRectangle.y + cursorRectangle.height - notesFlick.height
          }
        }
        Text {
          visible: notesField.text === "" && !notesField.activeFocus
          text: "What was said, what to do next…"
          font: notesField.font
          color: root.dim
          textFormat: Text.PlainText
        }
      }
    }
    Row {
      anchors.right: parent.right
      spacing: 8
      Repeater {
        model: [{ label: "Cancel", save: false }, { label: "Save", save: true }]
        delegate: Rectangle {
          required property var modelData
          width: 84
          height: 32
          radius: 16
          color: modelData.save ? root.s.tint("blue") : (actMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.14))
          Text {
            anchors.centerIn: parent
            text: modelData.label
            font.family: root.s.textFont
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: "white"
            textFormat: Text.PlainText
          }
          MouseArea {
            id: actMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: modelData.save ? root.saveNotes() : root.cancelNotes()
          }
        }
      }
    }
  }
}
