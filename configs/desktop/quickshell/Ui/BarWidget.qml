import QtQuick
import qs.Commons

Item {
  id: root

  property var bar: null
  property string moduleName: ""
  property var settings: ({})

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
}
