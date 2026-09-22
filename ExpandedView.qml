import QtQuick
import Quickshell
import "IslandModel.js" as Model

// The opened island. Top strip sits in the notch row (player / date on the
// left, battery on the right, the "camera" gap in the middle). Below it: the
// Now Playing card when something plays, otherwise a glanceable home view
// with the clock, this week, and quick timers.
Item {
  id: root

  property var s: null
  property bool active: false
  signal controlsClicked()

  readonly property int pad: 22
  readonly property int stripHeight: s.notchHeight

  // ---------------------------------------------------------------- top strip
  Item {
    id: strip
    x: root.pad
    width: parent.width - root.pad * 2
    height: root.stripHeight

    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6

      Artwork {
        visible: root.s.hasMedia && root.s.playerIcon !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: 14
        height: 14
        radius: 3
        source: root.s.playerIcon
        fallbackColor: "transparent"
      }
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: root.s.hasMedia ? (root.s.playerName || "Now Playing") : Qt.formatDateTime(root.s.now, "ddd d MMM")
        font.family: root.s.textFont
        font.pixelSize: 12
        font.weight: Font.Medium
        color: root.s.secondaryText
      }
      Text {
        textFormat: Text.PlainText
        visible: root.s.timerActive && root.s.hasMedia
        anchors.verticalCenter: parent.verticalCenter
        text: "  " + root.s.glyphs.timer + " " + Model.formatTime(Math.ceil(root.s.timerLeft))
        font.family: root.s.iconFont
        font.pixelSize: 12
        color: root.s.tint("orange")
      }
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8

      Rectangle {
        visible: root.s.micInUse
        anchors.verticalCenter: parent.verticalCenter
        width: 6
        height: 6
        radius: 3
        color: root.s.tint("orange")
      }
      Rectangle {
        visible: root.s.cameraInUse
        anchors.verticalCenter: parent.verticalCenter
        width: 6
        height: 6
        radius: 3
        color: root.s.tint("green")
      }
      Text {
        textFormat: Text.PlainText
        visible: root.s.dnd
        anchors.verticalCenter: parent.verticalCenter
        text: root.s.glyphs.moon
        font.family: root.s.iconFont
        font.pixelSize: 12
        color: root.s.tint("indigo")
      }
      Text {
        textFormat: Text.PlainText
        visible: root.s.hasBattery
        anchors.verticalCenter: parent.verticalCenter
        text: root.s.batteryPercent + "%"
        font.family: root.s.textFont
        font.pixelSize: 12
        font.weight: Font.Medium
        color: root.s.secondaryText
      }
      Text {
        textFormat: Text.PlainText
        visible: root.s.hasBattery
        anchors.verticalCenter: parent.verticalCenter
        text: Model.batteryGlyph(root.s.batteryPercent, root.s.charging)
        font.family: root.s.iconFont
        font.pixelSize: 15
        color: root.s.charging ? root.s.tint("green") : root.s.batteryPercent <= 20 ? root.s.tint("red") : root.s.textColor
      }
      // Opens the Control Center (Wi-Fi, Bluetooth, sound, power…).
      GlyphButton {
        anchors.verticalCenter: parent.verticalCenter
        glyph: "󰕮"
        glyphFont: root.s.iconFont
        glyphSize: 13
        color: root.s.textColor
        onClicked: root.controlsClicked()
      }
    }
  }

  // ---------------------------------------------------------------- now playing
  Item {
    id: player
    visible: root.s.hasMedia
    x: root.pad
    y: root.stripHeight + 8
    width: parent.width - root.pad * 2
    height: parent.height - y - 14

    Artwork {
      id: art
      width: 72
      height: 72
      radius: 14
      source: root.s.artLocal
      fallbackGlyph: root.s.glyphs.music
      glyphFont: root.s.iconFont
      glyphColor: root.s.mediaAccent
      scale: root.s.isPlaying ? 1 : 0.9
      Behavior on scale { SpringAnimation { spring: 4; damping: 0.35; epsilon: 0.005 } }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.s.mediaRaise()
      }
    }

    Column {
      anchors.left: art.right
      anchors.leftMargin: 14
      anchors.right: wave.left
      anchors.rightMargin: 12
      anchors.verticalCenter: art.verticalCenter
      spacing: 2

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.s.trackTitle || "Unknown"
        font.family: root.s.textFont
        font.pixelSize: 16
        font.weight: Font.DemiBold
        color: root.s.textColor
        elide: Text.ElideRight
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.s.trackArtist
        visible: text !== ""
        font.family: root.s.textFont
        font.pixelSize: 13
        color: root.s.secondaryText
        elide: Text.ElideRight
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.s.trackAlbum
        visible: text !== ""
        font.family: root.s.textFont
        font.pixelSize: 12
        color: Qt.rgba(root.s.textColor.r, root.s.textColor.g, root.s.textColor.b, 0.38)
        elide: Text.ElideRight
      }
    }

    Waveform {
      id: wave
      anchors.right: parent.right
      anchors.top: art.top
      anchors.topMargin: 4
      height: 22
      bars: 6
      barWidth: 3
      spacing: 2.5
      playing: root.s.isPlaying && root.active
      color: root.s.mediaAccent
    }

    // Progress: elapsed · scrubber · remaining.
    Item {
      id: progress
      anchors.top: art.bottom
      anchors.topMargin: 12
      width: parent.width
      height: 14
      visible: root.s.trackLength > 0

      readonly property real fraction: root.s.trackLength > 0 ? Model.clamp(root.s.trackPosition / root.s.trackLength, 0, 1) : 0

      Text {
        textFormat: Text.PlainText
        id: elapsed
        anchors.verticalCenter: parent.verticalCenter
        width: 40
        text: Model.formatTime(root.s.trackPosition)
        font.family: root.s.textFont
        font.pixelSize: 11
        font.features: { "tnum": 1 }
        color: root.s.secondaryText
      }
      Text {
        textFormat: Text.PlainText
        id: remaining
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 44
        horizontalAlignment: Text.AlignRight
        text: "-" + Model.formatTime(root.s.trackLength - root.s.trackPosition)
        font.family: root.s.textFont
        font.pixelSize: 11
        font.features: { "tnum": 1 }
        color: root.s.secondaryText
      }
      Item {
        anchors.left: elapsed.right
        anchors.right: remaining.left
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        height: 14

        Rectangle {
          id: track
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          // The scrubber thickens under the pointer, like iOS.
          height: scrub.containsMouse || scrub.pressed ? 8 : 5
          radius: height / 2
          color: root.s.trackColor
          Behavior on height { SpringAnimation { spring: 6; damping: 0.4; epsilon: 0.1 } }

          Rectangle {
            height: parent.height
            radius: parent.radius
            width: Math.max(parent.height, parent.width * (scrub.pressed ? scrub.dragFraction : progress.fraction))
            color: scrub.containsMouse || scrub.pressed ? root.s.textColor : Qt.rgba(root.s.textColor.r, root.s.textColor.g, root.s.textColor.b, 0.85)
          }
        }
        MouseArea {
          id: scrub
          anchors.fill: parent
          hoverEnabled: true
          enabled: root.s.player && root.s.player.canSeek
          cursorShape: Qt.PointingHandCursor
          property real dragFraction: 0
          onPressed: function(m) { dragFraction = Model.clamp(m.x / width, 0, 1) }
          onPositionChanged: function(m) { if (pressed) dragFraction = Model.clamp(m.x / width, 0, 1) }
          onReleased: root.s.mediaSeek(dragFraction)
        }
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      spacing: 26

      GlyphButton {
        anchors.verticalCenter: parent.verticalCenter
        glyph: root.s.glyphs.prev
        glyphFont: root.s.iconFont
        glyphSize: 22
        color: root.s.textColor
        hoverFill: root.s.controlFill
        enabledState: root.s.player && (root.s.player.canGoPrevious || root.s.player.canSeek)
        onClicked: root.s.mediaPrev()
      }
      GlyphButton {
        anchors.verticalCenter: parent.verticalCenter
        glyph: root.s.isPlaying ? root.s.glyphs.pause : root.s.glyphs.play
        glyphFont: root.s.iconFont
        glyphSize: 28
        color: root.s.textColor
        hoverFill: root.s.controlFill
        onClicked: root.s.mediaToggle()
      }
      GlyphButton {
        anchors.verticalCenter: parent.verticalCenter
        glyph: root.s.glyphs.next
        glyphFont: root.s.iconFont
        glyphSize: 22
        color: root.s.textColor
        hoverFill: root.s.controlFill
        enabledState: root.s.player && root.s.player.canGoNext
        onClicked: root.s.mediaNext()
      }
    }
  }

  // ---------------------------------------------------------------- home
  Item {
    id: home
    visible: !root.s.hasMedia
    x: root.pad
    y: root.stripHeight + 6
    width: parent.width - root.pad * 2
    height: parent.height - y - 16

    // Clock + date.
    Column {
      id: clock
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.topMargin: 4
      spacing: 0
      Text {
        textFormat: Text.PlainText
        text: Qt.formatDateTime(root.s.now, "HH:mm")
        font.family: root.s.textFont
        font.pixelSize: 46
        font.weight: Font.Light
        font.features: { "tnum": 1 }
        color: root.s.textColor
      }
      Text {
        textFormat: Text.PlainText
        text: Qt.formatDateTime(root.s.now, "dddd, d MMMM")
        font.family: root.s.textFont
        font.pixelSize: 13
        color: root.s.secondaryText
      }
    }

    // This week, today highlighted.
    Row {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: 10
      spacing: 4
      Repeater {
        model: { root.s.now; return Model.weekStrip(root.s.now) }
        Column {
          required property var modelData
          spacing: 3
          width: 30
          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.label
            font.family: root.s.textFont
            font.pixelSize: 10
            font.weight: Font.Medium
            color: root.s.secondaryText
          }
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 26
            height: 26
            radius: 13
            color: modelData.today ? (root.s.paletteName === "theme" ? root.s.tint("accent") : root.s.tint("red")) : "transparent"
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: modelData.day
              font.family: root.s.textFont
              font.pixelSize: 12
              font.weight: modelData.today ? Font.Bold : Font.Normal
              color: modelData.today ? "white" : root.s.textColor
            }
          }
        }
      }
    }

    // Timer: running countdown, or quick-start pills.
    Row {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      spacing: 8
      visible: !root.s.timerActive

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: root.s.glyphs.timer
        font.family: root.s.iconFont
        font.pixelSize: 15
        color: root.s.tint("orange")
      }
      Repeater {
        model: [1, 5, 10, 25]
        Rectangle {
          required property var modelData
          width: pillLabel.implicitWidth + 22
          height: 28
          radius: 14
          color: pillMouse.containsMouse ? Qt.rgba(1, 0.62, 0.04, 0.28) : Qt.rgba(1, 0.62, 0.04, 0.16)
          Behavior on color { ColorAnimation { duration: 140 } }
          scale: pillMouse.pressed ? 0.92 : 1
          Behavior on scale { SpringAnimation { spring: 6; damping: 0.35; epsilon: 0.005 } }
          Text {
            textFormat: Text.PlainText
            id: pillLabel
            anchors.centerIn: parent
            text: modelData + " min"
            font.family: root.s.textFont
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: root.s.tint("orange")
          }
          MouseArea {
            id: pillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.s.startTimer(modelData * 60)
          }
        }
      }
    }

    Row {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      spacing: 10
      visible: root.s.timerActive

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: root.s.glyphs.timer + "  " + Model.formatTime(Math.ceil(root.s.timerLeft))
        font.family: root.s.iconFont
        font.pixelSize: 22
        font.features: { "tnum": 1 }
        color: root.s.tint("orange")
        opacity: root.s.timerPausedLeft >= 0 ? 0.6 : 1
      }
      GlyphButton {
        anchors.verticalCenter: parent.verticalCenter
        glyph: root.s.timerPausedLeft >= 0 ? root.s.glyphs.play : root.s.glyphs.pause
        glyphFont: root.s.iconFont
        glyphSize: 16
        color: root.s.tint("orange")
        hoverFill: Qt.rgba(1, 0.62, 0.04, 0.2)
        onClicked: root.s.toggleTimerPause()
      }
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: cancelLabel.implicitWidth + 22
        height: 28
        radius: 14
        color: cancelMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.1)
        Text {
          textFormat: Text.PlainText
          id: cancelLabel
          anchors.centerIn: parent
          text: "Cancel"
          font.family: root.s.textFont
          font.pixelSize: 12
          font.weight: Font.DemiBold
          color: root.s.textColor
        }
        MouseArea {
          id: cancelMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.s.cancelTimer()
        }
      }
    }

    // Recording shortcut + DND state on the right.
    Row {
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      spacing: 8

      Rectangle {
        visible: root.s.recording
        width: recLabel.implicitWidth + 24
        height: 28
        radius: 14
        color: recMouse.containsMouse ? Qt.rgba(1, 0.27, 0.23, 0.32) : Qt.rgba(1, 0.27, 0.23, 0.2)
        Text {
          textFormat: Text.PlainText
          id: recLabel
          anchors.centerIn: parent
          text: "● Stop recording"
          font.family: root.s.textFont
          font.pixelSize: 12
          font.weight: Font.DemiBold
          color: root.s.tint("red")
        }
        MouseArea {
          id: recMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.s.stopRecording()
        }
      }
      Rectangle {
        width: dndLabel.implicitWidth + 24
        height: 28
        radius: 14
        color: root.s.dnd ? Qt.rgba(0.37, 0.36, 0.9, dndMouse.containsMouse ? 0.4 : 0.28) : (dndMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08))
        Behavior on color { ColorAnimation { duration: 160 } }
        Text {
          textFormat: Text.PlainText
          id: dndLabel
          anchors.centerIn: parent
          text: root.s.glyphs.moon + "  Focus"
          font.family: root.s.iconFont
          font.pixelSize: 12
          color: root.s.dnd ? root.s.tint("indigo") : root.s.secondaryText
        }
        MouseArea {
          id: dndMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.s.toggleDnd()
        }
      }
    }
  }
}
