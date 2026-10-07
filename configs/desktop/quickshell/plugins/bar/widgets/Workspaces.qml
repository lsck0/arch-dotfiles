import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function scrollWorkspace(direction) {
    var ids = root.workspaceIds
    if (ids.length === 0) return
    // this bar's monitor, not the globally focused one
    var currentId = root.activeWorkspaceId !== -1 ? root.activeWorkspaceId : ids[0]
    var index = ids.indexOf(currentId)
    if (index === -1) index = 0
    var nextIndex = (index + direction + ids.length) % ids.length
    root.focusWorkspace(ids[nextIndex])
  }

  readonly property var myMonitor: root.bar && root.bar.modelData
    ? Hyprland.monitorFor(root.bar.modelData) : null

  readonly property int activeWorkspaceId: {
    if (root.myMonitor && root.myMonitor.activeWorkspace)
      return root.myMonitor.activeWorkspace.id
    return Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.id : -1
  }

  // occupied workspaces plus the active one
  readonly property var workspaceIds: {
    var ids = []
    var values = Hyprland.workspaces.values
    var monitorActiveId = root.activeWorkspaceId

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0 || id > 10) continue
      if (root.myMonitor && values[i].monitor !== root.myMonitor) continue
      if (values[i].toplevels.values.length === 0 && id !== monitorActiveId) continue
      if (ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    // over the socket, no hyprctl process per click
    Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)
  // window dots under each number, one per window up to this
  readonly property int dotMax: 4

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  // one pill and underline slide to the focused cell; the leading edge moves first (worm stretch)
  property real pillTargetX: 0
  property real pillTargetW: 0
  property real pillX: 0
  property real pillRight: 0
  property bool pillShown: false
  property bool movingRight: true

  function placePill(x, w) {
    root.movingRight = x >= root.pillTargetX
    root.pillTargetX = x
    root.pillTargetW = w
    if (!root.pillShown) {
      // first placement jumps, no stretch from 0
      pillXBehavior.enabled = false
      pillRightBehavior.enabled = false
      root.pillX = x
      root.pillRight = x + w
      pillXBehavior.enabled = true
      pillRightBehavior.enabled = true
      root.pillShown = true
      return
    }
    root.pillX = x
    root.pillRight = x + w
  }

  Behavior on pillX {
    id: pillXBehavior
    NumberAnimation {
      duration: root.movingRight ? Style.motion.slow : Style.motion.fast
      easing.type: Easing.BezierSpline
      easing.bezierCurve: Style.motion.enter
    }
  }
  Behavior on pillRight {
    id: pillRightBehavior
    NumberAnimation {
      duration: root.movingRight ? Style.motion.fast : Style.motion.slow
      easing.type: Easing.BezierSpline
      easing.bezierCurve: Style.motion.enter
    }
  }

  Rectangle {
    visible: root.pillShown
    x: root.pillX
    y: Style.bar.pillInset
    width: Math.max(0, root.pillRight - root.pillX)
    height: parent.height - Style.bar.pillInset * 2
    radius: Style.shape.data
    color: Style.selectedFill
  }

  Rectangle {
    visible: root.pillShown
    x: root.pillX + Style.bar.pillInset
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.bar.pillInset
    width: Math.max(0, root.pillRight - root.pillX - Style.bar.pillInset * 2)
    height: Math.max(1, Style.space(2))
    color: Color.accent
    // static rule, its size animates only on a workspace switch
    layer.enabled: Style.fx.glow > 0 && !(root.bar && root.bar.quiet)
    layer.effect: Glow {}
  }

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds.length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds

      Item {
        id: cell
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property int windows: workspace !== null ? workspace.toplevels.values.length : 0
        readonly property bool occupied: windows > 0
        readonly property bool focused: root.activeWorkspaceId === modelData
        readonly property bool urgent: workspace !== null && workspace.urgent === true && !focused

        function report() { if (cell.focused) root.placePill(cell.x, cell.width) }
        onFocusedChanged: report()
        onXChanged: report()
        onWidthChanged: report()
        Component.onCompleted: report()

        implicitWidth: btn.implicitWidth
        implicitHeight: btn.implicitHeight

        WidgetButton {
          id: btn
          bar: root.bar
          text: cell.modelData === 10 ? "0" : String(cell.modelData)
          active: cell.focused
          activeColor: Color.accent
          foreground: cell.urgent ? Color.urgent : (root.bar ? root.bar.barForeground : Color.foreground)
          opacity: cell.occupied || cell.focused || cell.urgent ? 1 : Style.emphasis.faint
          horizontalMargin: Style.spacing.xs
          verticalPadding: Style.spacing.xs
          fixedWidth: root.vertical ? root.barSize : Style.space(20)
          fixedHeight: root.barSize
          onPressed: function() { root.focusWorkspace(cell.modelData) }
        }

        // one square per window, capped
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.bar.pillInset + Style.spacing.xxs * 2
          spacing: Style.spacing.xxs

          Repeater {
            model: Math.min(root.dotMax, cell.windows)
            Rectangle {
              width: Style.spacing.xxs
              height: Style.spacing.xxs
              radius: Style.shape.data
              color: cell.urgent ? Color.urgent : cell.focused ? Color.accent : Color.foreground
              opacity: cell.focused || cell.urgent ? 1 : Style.emphasis.dim
            }
          }
        }
      }
    }
  }

  // wheel only; clicks pass through to the buttons
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    onWheel: function(event) {
      root.scrollWorkspace(event.angleDelta.y < 0 ? 1 : -1)
    }
  }
}
