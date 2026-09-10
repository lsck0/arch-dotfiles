import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Verbatim from omarchy-shell, plus one addition upstream doesn't have
// either: scroll-to-switch (a MouseArea wheel handler cycling through
// `workspaceIds()`, wrapping at the ends) — not a fidelity gap, just a
// convenience this repo's own TODO.md flagged as missing.
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
    var ids = root.workspaceIds()
    if (ids.length === 0) return
    var currentId = Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.id : ids[0]
    var index = ids.indexOf(currentId)
    if (index === -1) index = 0
    var nextIndex = (index + direction + ids.length) % ids.length
    root.focusWorkspace(ids[nextIndex])
  }

  // Only workspaces that actually have a window on them, plus whichever one
  // is currently focused — dropped the old fixed 1-5 baseline that showed
  // four empty slots on a fresh session. The focused workspace stays even
  // when empty: otherwise switching to an empty workspace would blank the
  // whole widget, with no cell left to click back from.
  function workspaceIds() {
    var ids = []
    var values = Hyprland.workspaces.values
    var focusedId = Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.id : -1

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0 || id > 10) continue
      if (values[i].toplevels.values.length === 0 && id !== focusedId) continue
      if (ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      Item {
        id: cell
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        implicitWidth: btn.implicitWidth
        implicitHeight: btn.implicitHeight

        // Text-color-only focus indication (WidgetButton's `active` state)
        // was too subtle against this repo's muted pywal palette, and
        // occupied-but-unfocused workspaces already render at the same full
        // opacity — a filled pill is the only way to make "which one is
        // active" unambiguous at a glance. Same accent-fill token Clock's
        // calendar uses for "today".
        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: cell.focused ? Style.selectedFill : "transparent"
        }

        WidgetButton {
          id: btn
          bar: root.bar
          text: cell.modelData === 10 ? "0" : String(cell.modelData)
          active: cell.focused
          opacity: cell.occupied || cell.focused ? 1 : 0.5
          horizontalMargin: 6
          verticalPadding: 6
          fixedWidth: root.vertical ? root.barSize : Style.space(20)
          fixedHeight: root.barSize
          onPressed: function() { root.focusWorkspace(cell.modelData) }
        }
      }
    }
  }

  // acceptedButtons: NoButton so clicks pass through untouched to each
  // cell's own WidgetButton below — this MouseArea exists purely to catch
  // wheel events, which aren't gated by acceptedButtons the way
  // press/click are.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    onWheel: function(event) {
      root.scrollWorkspace(event.angleDelta.y < 0 ? 1 : -1)
    }
  }
}
