import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "separator"
  barPriority: 0

  readonly property int thickness: Math.max(1, Style.space(1))
  readonly property int pad: setting("pad", Style.bar.groupGap)

  property bool hasNeighbours: false

  readonly property Item ownLoader: parent
  readonly property Item section: ownLoader ? ownLoader.parent : null

  // a visible, non-empty widget on both sides of this one in its section
  function contentBeside() {
    if (!section) return false
    var siblings = Array.from(section.children)
    var index = siblings.indexOf(ownLoader)
    if (index < 0) return false
    function solid(loader) {
      var item = loader ? loader.item : null
      return !!item && item.visible && !loader.dropped && item.moduleName !== "separator" && item.implicitWidth > 0
    }
    return siblings.slice(0, index).some(solid) && siblings.slice(index + 1).some(solid)
  }

  Timer {
    id: settle
    interval: 32
    onTriggered: root.hasNeighbours = root.contentBeside()
  }

  Connections {
    target: root.bar
    enabled: root.bar !== null
    function onLayoutRevisionChanged() { settle.restart() }
  }

  Component.onCompleted: settle.restart()

  visible: hasNeighbours
  implicitWidth: thickness + pad * 2
  implicitHeight: Style.bar.sizeHorizontal

  Label {
    anchors.centerIn: parent
    text: "::"
    color: Colors.accentText
    opacity: Style.emphasis.faint
    font.letterSpacing: Style.headerTracking
    layer.enabled: Style.fx.glow > 0
    layer.effect: Glow {}
  }
}
