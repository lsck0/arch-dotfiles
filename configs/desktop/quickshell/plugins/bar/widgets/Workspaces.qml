pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "workspaces"
  barPriority: 100

  // hyprland_keybindings.lua WORKSPACE_COUNT: workspaces 1 to 10 on the keys 1 to 0
  readonly property int workspaceCount: 10

  function workspaceById(id) { return Hyprland.workspaces.values.find(w => w.id === id) || null }

  function scrollWorkspace(direction) {
    var ids = root.workspaceIds
    if (ids.length === 0) return
    var currentId = root.activeWorkspaceId !== -1 ? root.activeWorkspaceId : ids[0]
    var index = Math.max(0, ids.indexOf(currentId))
    root.focusWorkspace(ids[(index + direction + ids.length) % ids.length])
  }

  readonly property var myMonitor: root.bar && root.bar.modelData
    ? Hyprland.monitorFor(root.bar.modelData) : null

  readonly property int activeWorkspaceId: {
    if (root.myMonitor && root.myMonitor.activeWorkspace)
      return root.myMonitor.activeWorkspace.id
    return Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.id : -1
  }

  // a string, so window churn that leaves the id list as it was does not rebuild the cells
  readonly property string workspaceKey: {
    var ids = []
    var values = Hyprland.workspaces.values
    var monitorActiveId = root.activeWorkspaceId

    for (let i = 0; i < values.length; i++) {
      let id = values[i].id
      if (id <= 0 || id > root.workspaceCount) continue
      if (root.myMonitor && values[i].monitor !== root.myMonitor) continue
      if (values[i].toplevels.values.length === 0 && id !== monitorActiveId) continue
      if (ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids.join(" ")
  }
  readonly property var workspaceIds: workspaceKey === "" ? [] : workspaceKey.split(" ").map(Number)

  function focusWorkspace(id) {
    Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
  }

  readonly property real trailingGap: Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  property real pillTargetX: 0
  property real pillX: 0
  property real pillRight: 0
  property bool pillShown: false
  property bool movingRight: true

  function placePill(x, w) {
    root.movingRight = x >= root.pillTargetX
    root.pillTargetX = x
    if (!root.pillShown) {
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
    color: Colors.accent
    layer.enabled: Style.fx.glow > 0 && !(root.bar && root.bar.quiet)
    layer.effect: Glow {}
  }

  RowLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    spacing: Style.space(1)

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
          text: String(cell.modelData % root.workspaceCount)
          active: cell.focused
          activeColor: Colors.textOnFill(Colors.accent, Style.selectedFill)
          foreground: cell.urgent ? Colors.urgentText
            : cell.occupied ? Colors.bar.text : Colors.textDim
          hoverFill: !cell.focused
          fixedWidth: Style.space(20)
          onPressed: function() { root.focusWorkspace(cell.modelData) }
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    readonly property int wheelNotchDelta: 120
    property int wheelAccumDelta: 0
    onWheel: function(event) {
      if (event.angleDelta.y === 0) return
      wheelAccumDelta += event.angleDelta.y
      while (wheelAccumDelta <= -wheelNotchDelta) {
        wheelAccumDelta += wheelNotchDelta
        root.scrollWorkspace(1)
      }
      while (wheelAccumDelta >= wheelNotchDelta) {
        wheelAccumDelta -= wheelNotchDelta
        root.scrollWorkspace(-1)
      }
    }
  }
}
