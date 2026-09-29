import QtQuick
import qs.Commons

Item {
  id: root

  property QtObject bar: null
  property string moduleName: ""
  property var settings: ({})

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // x in bar-content coordinates
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

  // own x does not change when a parent section moves
  Connections {
    target: root.bar
    enabled: root.bar !== null
    function onLayoutRevisionChanged() { root.refreshBarX() }
    function onWidthChanged() { root.refreshBarX() }
  }

  // deferred: layout has not run yet at completion
  Component.onCompleted: refreshBarX()
}
