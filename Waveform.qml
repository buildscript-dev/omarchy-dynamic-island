import QtQuick

// The live music "waveform": a handful of rounded bars that dance while
// playing and settle into short pills when paused. Tinted with the album's
// signature color, as iOS does for its music activity.
Item {
  id: root

  property bool playing: false
  property color color: "white"
  property int bars: 5
  property real barWidth: 2.6
  property real spacing: 2.2
  // Real levels (0..1) from cava; empty means make up a dance.
  property var levels: []

  implicitWidth: bars * barWidth + (bars - 1) * spacing
  implicitHeight: 16

  Row {
    anchors.centerIn: parent
    spacing: root.spacing

    Repeater {
      model: root.bars

      Rectangle {
        id: bar
        required property int index
        // Middle bars swing wider than the edges, so the group reads as a
        // waveform envelope instead of random noise.
        readonly property real envelope: 1 - Math.abs(index - (root.bars - 1) / 2) / root.bars
        property real level: 0.25

        width: root.barWidth
        // Live: bass drives the middle bars, treble the edges, shaped by the
        // same envelope as the made-up dance so the wave keeps its look.
        readonly property real band: root.levels.length ? root.levels[Math.min(root.levels.length - 1, Math.floor(Math.abs(index - (root.bars - 1) / 2) / ((root.bars) / 2) * root.levels.length))] : 0
        readonly property real live: root.levels.length ? 0.22 + band * 0.78 * envelope + 0.1 * band : -1
        height: Math.max(root.barWidth, root.height * (!root.playing ? 0.18 : live >= 0 ? live : level))
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: root.color
        opacity: root.playing ? 1 : 0.55

        Behavior on height { SpringAnimation { spring: 5; damping: 0.35; epsilon: 0.2 } }
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on color { ColorAnimation { duration: 500 } }

        Timer {
          running: root.playing && root.visible && !root.levels.length
          repeat: true
          interval: 150 + bar.index * 37
          onTriggered: bar.level = 0.22 + Math.random() * 0.78 * bar.envelope + 0.1
        }
      }
    }
  }
}
