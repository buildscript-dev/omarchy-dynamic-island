import QtQuick

// History: what the island did lately (Activity) and past notifications,
// opened by scrolling down on the island. Cards scroll the way the iPhone
// lock screen stacks them: a card leaving the top shrinks and fades under
// the edge, one arriving from the bottom grows into place. Swipe a card
// sideways to dismiss it; scroll up at the top to close.
Item {
  id: root

  property var s: null
  property bool active: false
  onActiveChanged: if (active) { list.targetY = 0; list.overscroll = 0 }
  signal closeRequested()

  readonly property color fg: s.textColor
  readonly property color dim: s.secondaryText
  readonly property color cardFill: Qt.rgba(fg.r, fg.g, fg.b, 0.1)
  readonly property color cardHover: Qt.rgba(fg.r, fg.g, fg.b, 0.15)

  readonly property int pad: 14
  readonly property int preferredWidth: Math.max(380, s.notificationWidth)
  readonly property int preferredHeight: Math.min(460, Math.max(120, list.contentHeight + 2 * pad))

  // One flat list, section headers included, so everything scrolls together.
  readonly property var rows: {
    var out = []
    if (s.recent.length > 0) {
      out.push({ head: "Activity", which: "recent" })
      for (var i = 0; i < s.recent.length; i++) out.push({ act: s.recent[i] })
    }
    if (s.history.length > 0) {
      out.push({ head: "Notifications", which: "history" })
      for (var j = 0; j < s.history.length; j++) out.push({ notif: s.history[j] })
    }
    return out
  }

  Text {
    visible: root.rows.length === 0
    anchors.centerIn: parent
    text: "No recent activity"
    font.family: root.s.textFont
    font.pixelSize: 13
    color: root.dim
    textFormat: Text.PlainText
  }

  // The view scrolls itself rather than leaving the wheel to the list, so an
  // up-scroll at the top can always hand back to the island (closeRequested).
  WheelHandler {
    onWheel: function(event) {
      var dy = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y
      var max = Math.max(0, list.contentHeight - list.height)
      if (dy > 0 && list.targetY <= 0.5) {
        list.overscroll += dy
        if (list.overscroll >= 120) { list.overscroll = 0; root.closeRequested() }
        return
      }
      list.overscroll = 0
      list.targetY = Math.max(0, Math.min(max, list.targetY - dy))
    }
  }

  ListView {
    id: list
    anchors.fill: parent
    anchors.margins: root.pad
    clip: true
    spacing: 8
    interactive: false
    property real targetY: 0
    contentY: targetY
    Behavior on contentY { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    model: root.rows
    // New entries glide in instead of popping.
    add: Transition { NumberAnimation { properties: "opacity"; from: 0; to: 1; duration: 220 } }
    displaced: Transition { NumberAnimation { properties: "y"; duration: 260; easing.type: Easing.OutCubic } }

    property real overscroll: 0

    delegate: Item {
      id: row
      required property var modelData
      required property int index
      width: list.width
      height: modelData.head ? 24 : card.height

      // Where this row sits in the viewport; drives the stack effect.
      readonly property real viewTop: y - list.contentY
      readonly property real viewBelow: viewTop + height - list.height
      readonly property real stackScale: viewTop < 0 ? Math.max(0.86, 1 + viewTop / 360)
        : viewBelow > 0 ? Math.max(0.9, 1 - viewBelow / 420) : 1
      scale: root.s.reduceMotion ? 1 : stackScale
      opacity: viewTop < 0 ? Math.max(0, 1 + viewTop / (height * 1.1)) : viewBelow > 0 ? Math.max(0.25, 1 - viewBelow / 160) : 1
      transformOrigin: viewTop < 0 ? Item.Bottom : Item.Top

      // ------------------------------------------------ section header
      Item {
        visible: !!row.modelData.head
        anchors.fill: parent
        Text {
          anchors.left: parent.left
          anchors.leftMargin: 4
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData.head || ""
          font.family: root.s.textFont
          font.pixelSize: 15
          font.weight: Font.Bold
          color: root.fg
          textFormat: Text.PlainText
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: 4
          anchors.verticalCenter: parent.verticalCenter
          text: "Clear"
          font.family: root.s.textFont
          font.pixelSize: 12
          color: clearMouse.containsMouse ? root.fg : root.dim
          textFormat: Text.PlainText
          MouseArea {
            id: clearMouse
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.modelData.which === "history" ? root.s.clearHistory() : root.s.clearRecent()
          }
        }
      }

      // ------------------------------------------------ card
      Rectangle {
        id: card
        visible: !row.modelData.head
        width: parent.width
        height: row.modelData.head ? 0 : Math.max(52, cardText.implicitHeight + 18)
        radius: 18
        color: cardMouse.containsMouse ? root.cardHover : root.cardFill
        Behavior on x { enabled: !cardDrag.active; SpringAnimation { spring: 4; damping: 0.4 } }
        opacity: 1 - Math.min(1, Math.abs(x) / (width * 0.6))

        readonly property var e: row.modelData.act || row.modelData.notif || ({})
        readonly property bool isNotif: !!row.modelData.notif

        function dismiss() {
          if (isNotif) root.s.removeHistory(e.file)
          else root.s.removeRecent(e)
        }

        DragHandler {
          id: cardDrag
          yAxis.enabled: false
          onActiveChanged: if (!active) {
            if (Math.abs(card.x) > card.width * 0.3) card.dismiss()
            else card.x = 0
          }
        }
        MouseArea {
          id: cardMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: card.isNotif ? Qt.PointingHandCursor : Qt.ArrowCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) { card.dismiss(); return }
            if (card.isNotif) {
              if (!root.s.openForApp(card.e.app)) root.s.fire(["omarchy-shell", "-q", "notifications", "invokeLast"], 10)
              root.closeRequested()
            }
          }
        }

        Artwork {
          id: icon
          x: 9
          anchors.verticalCenter: parent.verticalCenter
          width: 34
          height: 34
          radius: 10
          source: card.isNotif ? (card.e.image || "") : ""
          fallbackGlyph: card.isNotif ? root.s.glyphs.bell : (card.e.icon || root.s.glyphs.bell)
          glyphFont: root.s.iconFont
          glyphColor: card.isNotif ? (card.e.urgent ? root.s.tint("red") : root.fg) : root.s.tint(card.e.tint || "white")
          fallbackColor: Qt.rgba(1, 1, 1, 0.1)
        }
        Column {
          id: cardText
          anchors.left: icon.right
          anchors.leftMargin: 10
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1
          Row {
            width: parent.width
            Text {
              width: parent.width - when.width
              text: card.isNotif ? (card.e.app || "") : (card.e.title || "")
              font.family: root.s.textFont
              font.pixelSize: card.isNotif ? 11 : 13
              font.weight: card.isNotif ? Font.Normal : Font.DemiBold
              color: card.isNotif ? root.dim : root.fg
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }
            Text {
              id: when
              text: root.s.timeAgo(card.e.time || 0)
              font.family: root.s.textFont
              font.pixelSize: 11
              color: root.dim
              textFormat: Text.PlainText
            }
          }
          Text {
            width: parent.width
            visible: text !== ""
            text: card.isNotif ? (card.e.title || "") : (card.e.value || "")
            font.family: root.s.textFont
            font.pixelSize: 13
            font.weight: card.isNotif ? Font.DemiBold : Font.Normal
            color: card.isNotif ? (card.e.urgent ? root.s.tint("red") : root.fg) : root.dim
            elide: Text.ElideRight
            textFormat: Text.PlainText
          }
          Text {
            width: parent.width
            visible: card.isNotif && text !== ""
            text: card.isNotif ? (card.e.body || "") : ""
            font.family: root.s.textFont
            font.pixelSize: 12
            color: root.dim
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            textFormat: Text.PlainText
          }
        }
      }
    }
  }
}
