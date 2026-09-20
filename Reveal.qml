import QtQuick
import QtQuick.Effects

// Content layer that morphs in and out the way Dynamic Island content does:
// the outgoing view drops away fast (blur up, fade, shrink a touch) while the
// shape is still moving; the incoming view waits a beat for the shape to open
// and then resolves from a soft blur into place.
Item {
  id: root

  property bool shown: false
  property real reveal: 0
  // Delay before the incoming content starts resolving, so the shape leads.
  property int inDelay: 110
  property int inDuration: 340
  property int outDuration: 120

  opacity: reveal
  scale: 0.92 + 0.08 * reveal
  transformOrigin: Item.Top
  visible: reveal > 0.005
  enabled: shown

  layer.enabled: reveal > 0.005 && reveal < 0.995
  layer.smooth: true
  layer.effect: MultiEffect {
    blurEnabled: true
    blurMax: 24
    blur: 1 - root.reveal
    autoPaddingEnabled: true
  }

  function apply() {
    showAnim.stop()
    hideAnim.stop()
    if (shown) showAnim.start()
    else hideAnim.start()
  }
  onShownChanged: apply()
  Component.onCompleted: reveal = shown ? 1 : 0

  SequentialAnimation {
    id: showAnim
    PauseAnimation { duration: root.inDelay }
    NumberAnimation { target: root; property: "reveal"; to: 1; duration: root.inDuration; easing.type: Easing.OutCubic }
  }
  NumberAnimation {
    id: hideAnim
    target: root
    property: "reveal"
    to: 0
    duration: root.outDuration
    easing.type: Easing.InQuad
  }
}
