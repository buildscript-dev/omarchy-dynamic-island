import QtQuick
import qs.Ui

// The island's footprint in the bar. It draws nothing — the notch itself is
// an overlay layer above the bar — but it reserves the notch's width in the
// bar's center section, so bar widgets flow around the notch the way the
// macOS menu bar flows around the camera housing.
BarWidget {
  id: root
  moduleName: "io.github.buildscript-dev.dynamic-island"

  readonly property var service: root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function"
    ? root.bar.shell.serviceFor(root.moduleName) : null
  readonly property int footprint: root.service ? root.service.barFootprint : Number(root.setting("notchWidth", 200)) + 12

  visible: !root.vertical
  implicitWidth: root.vertical ? 0 : root.footprint + 8
  implicitHeight: root.barSize

  Behavior on implicitWidth {
    SpringAnimation { spring: 3.3; damping: 0.3; epsilon: 0.25 }
  }
}
