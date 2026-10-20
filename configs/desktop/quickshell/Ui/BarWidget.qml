import QtQuick
import qs.Commons

Item {
  id: root

  // untyped: Ui cannot import plugins/bar back
  property var bar: null
  property string moduleName: ""
  property var settings: ({})

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // false where a left click already does something else (Media plays, Homelab opens its homepage)
  property bool panelPinOnClick: true
  readonly property bool panelPinnable: panelPinOnClick && bar !== null
    && bar.panelNames.indexOf(moduleName) !== -1

  // above the widget's own MouseArea: a passive tap grab lets the press through to it. No HoverHandler here: it
  // takes the hover, so the MouseArea below never gets onEntered and no panel opens on hover (blocking: false does
  // not help); each widget's MouseArea sets the pointing cursor itself
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

  // deferred: layout has not run yet at completion
  Component.onCompleted: refreshBarX()
}
