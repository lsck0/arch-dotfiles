import QtQuick
import qs.Commons

Item {
  id: root

  property var bar: null
  property string moduleName: ""
  property var settings: ({})
  // a bar too narrow for every widget drops the lowest first, across all three sections
  property int barPriority: 0
  // set by BarSection while the widget is dropped for width: it stays visible but takes no space
  property bool dropped: false

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  property bool panelPinOnClick: true
  readonly property bool panelPinnable: panelPinOnClick && bar !== null
    && bar.panelNames.indexOf(moduleName) !== -1

  Item {
    anchors.fill: parent
    z: 1000
    enabled: root.panelPinnable
    TapHandler {
      acceptedButtons: Qt.LeftButton
      onTapped: root.bar.panelClick(root.moduleName)
    }
  }

  property real barX: 0

  function refreshBarX() { barXSettle.restart() }

  Timer {
    id: barXSettle
    interval: 16
    repeat: false
    onTriggered: {
      if (!root.bar || !root.bar.contentItem) return
      root.barX = root.mapToItem(root.bar.contentItem, 0, 0).x
    }
  }

  onXChanged: refreshBarX()
  onWidthChanged: refreshBarX()

  Connections {
    target: root.bar
    enabled: root.bar !== null
    function onLayoutRevisionChanged() { root.refreshBarX() }
    function onWidthChanged() { root.refreshBarX() }
  }

  Component.onCompleted: refreshBarX()

  // a widget with a hover panel: entering opens it, leaving starts its close; hoverFill tints the trigger meanwhile
  property bool hoverPanel: false
  property bool hoverFill: false
  property int hoverCursor: Qt.PointingHandCursor
  readonly property bool hovered: hover.hovered

  Rectangle {
    anchors.fill: parent
    z: -1
    visible: root.hoverFill
    radius: Style.shape.data
    color: hover.hovered ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
  }

  HoverHandler {
    id: hover
    enabled: root.hoverPanel || root.hoverFill
    cursorShape: root.hoverCursor
    onHoveredChanged: {
      if (!root.hoverPanel || !root.bar) return
      if (hovered) root.bar.hoverOpen(root.moduleName)
      else root.bar.hoverTriggerExit(root.moduleName)
    }
  }
}
