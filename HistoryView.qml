import QtQuick
import "IslandModel.js" as Model

// History: what the island did lately (Activity) and past notifications,
// opened by scrolling down on the island. Cards scroll the way the iPhone
// lock screen stacks them: a card leaving the top shrinks and fades under
// the edge, one arriving from the bottom grows into place. Swipe a card
// sideways to dismiss it; scroll up at the top to close.
Item {
  id: root

  property var s: null
  property bool active: false
  // "glance" = Needs a look + Activity (scroll up on the pill); "notifs" = every other notification (end of the scroll down).
  property string kind: "notifs"
  onActiveChanged: if (active) { list.targetY = 0; list.overscroll = 0 }
  signal closeRequested()

  readonly property color fg: s.textColor
  readonly property color dim: s.secondaryText
  readonly property color cardFill: Qt.rgba(fg.r, fg.g, fg.b, 0.1)
  readonly property color cardHover: Qt.rgba(fg.r, fg.g, fg.b, 0.15)

  readonly property int pad: 14
  readonly property int preferredWidth: Math.max(380, s.notificationWidth)
  readonly property int preferredHeight: Math.min(460, Math.max(120, list.contentHeight + 2 * pad))

  // What deserves a look: urgent, one-time codes and other sensitive content, missed calls, low battery, failures.
  // Island chatter (sound, screenshots) never counts.
  function codeOf(n) { return root.s.codeOf(n) }

  function isImportant(n) {
    var app = String(n.app || "").toLowerCase()
    var text = (String(n.title || "") + " " + String(n.body || "")).toLowerCase()
    if (/omarchy-action|notify-send|^sound|screenshot|stream started/.test(app + " " + text)) return false
    // A card Android blanked out says nothing; its SMS arrives whole on its own card. Kept in Notifications only.
    if (Model.isRedacted(n)) return false
    if (n.urgent || codeOf(n) !== "") return true
    return /sensitive|otp|one-time|verification|password|security|missed|low battery|failed|critical/.test(text)
  }

  // A colour per app: brand colours for the usual ones, a stable hue from the name for the rest.
  readonly property var brands: ({ whatsapp: "#25D366", gmail: "#EA4335", messages: "#34C759", telegram: "#2AABEE",
    discord: "#5865F2", signal: "#3A76F0", slack: "#E01E5A", spotify: "#1DB954", firefox: "#FF7139", chrome: "#4285F4",
    calendar: "#4285F4", phone: "#34C759", "galaxy s24": "#0A84FF", github: "#A371F7", instagram: "#E1306C",
    youtube: "#FF0033", amazon: "#FF9900", "omarchy-action": "#30D5C8", battery: "#FFD60A" })
  function accentOf(n, important) {
    if (important) return n.urgent ? "#FF453A" : "#FF9F0A"
    var a = String(n.app || "").toLowerCase()
    for (var k in brands) if (a.indexOf(k) >= 0) return brands[k]
    var h = 0
    for (var i = 0; i < a.length; i++) h = (h * 31 + a.charCodeAt(i)) % 360
    return Qt.hsla(h / 360, 0.7, 0.58, 1)
  }

  // One flat list, section headers included, so everything scrolls together.
  readonly property var rows: {
    var out = []
    var imp = [], rest = []
    for (var k = 0; k < s.history.length; k++) (isImportant(s.history[k]) && imp.length < 4 ? imp : rest).push(s.history[k])
    if (kind === "glance") {
      if (imp.length > 0) {
        out.push({ head: "Needs a look", which: "important" })
        for (var m = 0; m < imp.length; m++) out.push({ notif: imp[m], important: true })
      }
      if (s.recent.length > 0) {
        out.push({ head: "Activity", which: "recent" })
        for (var i = 0; i < s.recent.length; i++) out.push({ act: s.recent[i] })
      }
    } else if (rest.length > 0) {
      out.push({ head: "Notifications", which: "history" })
      for (var j = 0; j < rest.length; j++) out.push({ notif: rest[j] })
    }
    return out
  }

  Text {
    visible: root.rows.length === 0
    anchors.centerIn: parent
    text: root.kind === "glance" ? "Nothing needs a look" : "No notifications"
    font.family: root.s.textFont
    font.pixelSize: Model.TYPE.subhead
    color: root.dim
    textFormat: Text.PlainText
  }

  // The island hands every scroll here (IslandWindow.islandWheel): it moves
  // the list, and an up-scroll once the list is at its top closes History,
  // back to the island's own size.
  function wheel(dy) {
    var max = Math.max(0, list.contentHeight - list.height)
    if (dy > 0 && list.targetY <= 0.5) {
      list.overscroll += dy
      if (list.overscroll >= 120) { list.overscroll = 0; root.closeRequested() }
      return
    }
    list.overscroll = 0
    list.targetY = Math.max(0, Math.min(max, list.targetY - dy))
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

      // Where this row sits in the viewport; rows fade at the edges but keep full width so every card lines up.
      readonly property real viewTop: y - list.contentY
      readonly property real viewBelow: viewTop + height - list.height
      opacity: viewTop < 0 ? Math.max(0, 1 + viewTop / (height * 1.1)) : viewBelow > 0 ? Math.max(0.25, 1 - viewBelow / 160) : 1

      // ------------------------------------------------ section header
      Item {
        visible: !!row.modelData.head
        anchors.fill: parent
        readonly property color hue: row.modelData.which === "important" ? "#FF9F0A" : "#FFFFFF"
        Rectangle {
          id: dot
          x: 4
          anchors.verticalCenter: parent.verticalCenter
          width: 8; height: 8; radius: 4
          color: parent.hue
        }
        Text {
          anchors.left: dot.right
          anchors.leftMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData.head || ""
          font.family: root.s.textFont
          font.pixelSize: Model.TYPE.callout
          font.weight: Font.Bold
          color: root.fg
          textFormat: Text.PlainText
        }
        Rectangle {
          anchors.right: parent.right
          anchors.rightMargin: 2
          anchors.verticalCenter: parent.verticalCenter
          visible: row.modelData.which !== "important"
          width: clearText.implicitWidth + 18
          height: 20
          radius: 10
          color: Qt.rgba(1, 1, 1, clearMouse.containsMouse ? 0.2 : 0.12)
          Text {
            id: clearText
            anchors.centerIn: parent
            text: "Clear"
            font.family: root.s.textFont
            font.pixelSize: Model.TYPE.footnote
            font.weight: Font.DemiBold
            color: Qt.rgba(1, 1, 1, 0.8)
            textFormat: Text.PlainText
          }
          MouseArea {
            id: clearMouse
            anchors.fill: parent
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
        height: row.modelData.head ? 0 : Math.max(58, cardText.implicitHeight + 22)
        radius: 18
        readonly property color accent: isNotif ? root.accentOf(e, !!row.modelData.important) : root.s.tint(e.tint || "white")
        color: cardMouse.containsMouse ? "#1c1c1e" : "#0e0e10"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
        Behavior on x { enabled: !cardDrag.active; SpringAnimation { spring: 4; damping: 0.4 } }
        opacity: 1 - Math.min(1, Math.abs(x) / (width * 0.6))

        readonly property var e: row.modelData.act || row.modelData.notif || ({})
        readonly property bool isNotif: !!row.modelData.notif
        readonly property string foundCode: isNotif ? root.codeOf(e) : ""
        // A code is shown and copied only while it can still work: the minutes its message names, else ten.
        readonly property bool codeStale: foundCode !== "" && Date.now() - (e.time || 0) > ((e.minutes || Model.otpMinutes(root.s.textOf(e)) || 10) * 60000)
        readonly property string code: codeStale ? "" : foundCode

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
            if (card.isNotif && card.code !== "") { root.s.copyCode(card.code); root.closeRequested(); return }
            // Its own action, else its app; never "the newest popup", which is some other notification.
            if (card.isNotif) {
              root.s.openNotif(card.e, false, card.codeStale)
              root.closeRequested()
            }
          }
        }

        Artwork {
          id: icon
          x: 10
          anchors.verticalCenter: parent.verticalCenter
          width: 38
          height: 38
          radius: 11
          source: card.e.image || ""
          fallbackGlyph: card.isNotif ? root.s.glyphs.bell : (card.e.icon || root.s.glyphs.bell)
          glyphFont: root.s.iconFont
          glyphColor: "white"
          fallbackColor: Qt.rgba(1, 1, 1, 0.14)
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
              text: card.isNotif ? String(card.e.app || "").toUpperCase() : (card.e.title || "")
              font.family: root.s.textFont
              font.pixelSize: card.isNotif ? 10 : 14
              font.weight: Font.Bold
              font.letterSpacing: card.isNotif ? 0.6 : 0
              color: card.isNotif ? Qt.rgba(1, 1, 1, 0.55) : "white"
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }
            Text {
              id: when
              text: root.s.timeAgo(card.e.time || 0)
              font.family: root.s.textFont
              font.pixelSize: Model.TYPE.caption
              color: Qt.rgba(1, 1, 1, 0.5)
              font.weight: Font.DemiBold
              textFormat: Text.PlainText
            }
          }
          Text {
            width: parent.width
            visible: text !== ""
            text: card.codeStale ? "Code expired" : card.code !== "" ? (root.s.copiedCode === card.code ? "Copied " : "Code ") + Model.otpGroup(card.code) + (root.s.copiedCode === card.code ? "" : "  ·  tap to copy") : card.isNotif ? (card.e.title || "") : (card.e.value || "")
            font.family: root.s.textFont
            font.pixelSize: card.isNotif ? 14 : 12
            font.weight: card.isNotif ? Font.Bold : Font.Normal
            color: card.isNotif ? (card.e.urgent ? "#FF453A" : "white") : Qt.rgba(1, 1, 1, 0.6)
            elide: Text.ElideRight
            textFormat: Text.PlainText
          }
          Text {
            width: parent.width
            visible: card.isNotif && text !== ""
            // With a code, the body would repeat the digits (stale ones too): say where it came from instead.
            text: !card.isNotif ? "" : card.foundCode === "" ? (card.e.body || "")
              : card.e.app === "One-time code" ? (card.e.title || "") : (card.e.title ? (card.e.app || "") + " · " + card.e.title : "")
            font.family: root.s.textFont
            font.pixelSize: 12
            color: Qt.rgba(1, 1, 1, 0.68)
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
