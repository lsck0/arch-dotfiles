import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Verbatim from omarchy-shell, plus one addition upstream doesn't have
// either: scroll-to-switch (a MouseArea wheel handler cycling through
// `workspaceIds()`, wrapping at the ends) — not a fidelity gap, just a
// convenience this repo's own notes (now research/ROADMAP.md) flagged as
// missing.
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
    // This bar's own monitor, not the globally focused one — scrolling on a
    // secondary bar used to start counting from whatever workspace the OTHER
    // monitor was on, so the first tick jumped somewhere unrelated.
    var currentId = root.activeWorkspaceId !== -1 ? root.activeWorkspaceId : ids[0]
    var index = ids.indexOf(currentId)
    if (index === -1) index = 0
    var nextIndex = (index + direction + ids.length) % ids.length
    root.focusWorkspace(ids[nextIndex])
  }

  // This bar's own output, as a HyprlandMonitor — not a screen name string,
  // so it compares directly against HyprlandWorkspace.monitor below. Null
  // until Hyprland has actually reported monitors (or on a bar with no
  // `bar.modelData`, e.g. under a test harness), in which case every
  // workspace passes rather than the bar going permanently blank.
  readonly property var myMonitor: root.bar && root.bar.modelData
    ? Hyprland.monitorFor(root.bar.modelData) : null

  // THE workspace this bar's own monitor is showing. Every "which one is
  // current" question in this widget must go through here: Hyprland's
  // `focusedWorkspace` is compositor-global (whichever monitor last had input
  // focus), so reading it directly makes a secondary bar describe the primary
  // monitor's state. That was fixed once for the visible-workspace list and
  // missed here, which is why the focus pill vanished from a secondary bar the
  // moment the pointer left it.
  //
  // Falls back to the global focus only while Hyprland has not reported this
  // monitor yet (first frame, or a bar with no modelData under a harness).
  readonly property int activeWorkspaceId: {
    if (root.myMonitor && root.myMonitor.activeWorkspace)
      return root.myMonitor.activeWorkspace.id
    return Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.id : -1
  }

  // Only workspaces that actually have a window on them, plus whichever one
  // is currently focused — dropped the old fixed 1-5 baseline that showed
  // four empty slots on a fresh session. The focused workspace stays even
  // when empty: otherwise switching to an empty workspace would blank the
  // whole widget, with no cell left to click back from.
  //
  // Filtered to THIS bar's own monitor. Every bar used to list every
  // workspace on every monitor — a workspace living on DP-2 still showed
  // (and was clickable, jumping the pointer to another screen) on DP-1's
  // bar. Hyprland's own multi-monitor model is "each workspace belongs to
  // exactly one monitor", so this list should too.
  function workspaceIds() {
    var ids = []
    var values = Hyprland.workspaces.values
    // Per-monitor active workspace, NOT Hyprland.focusedWorkspace — that's
    // global (whichever monitor last had input focus). Keying the "keep an
    // empty workspace visible" rule off it meant switching monitors changed
    // every OTHER bar's idea of "focused" too: move off an empty workspace 3
    // on monitor A onto monitor B, and A's bar immediately dropped 3 (it's
    // empty and no longer *globally* focused) until the mouse re-entered A.
    // Same bug behind "non-main taskbars should still show" — a secondary
    // monitor's own active-but-empty workspace was being hidden on its own
    // bar for the same reason.
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
        readonly property bool focused: root.activeWorkspaceId === modelData

        implicitWidth: btn.implicitWidth
        implicitHeight: btn.implicitHeight

        // Text-color-only focus indication (WidgetButton's `active` state)
        // was too subtle against this repo's muted wallust palette, and
        // occupied-but-unfocused workspaces already render at the same full
        // opacity — a filled pill is the only way to make "which one is
        // active" unambiguous at a glance. Same accent-fill token Clock's
        // calendar uses for "today".
        // Inset top and bottom. Filling the cell made the pill run edge to
        // edge on a 30px bar, where it read as a block of background colour
        // rather than as a control sitting on the bar.
        Rectangle {
          anchors.fill: parent
          anchors.topMargin: Style.bar.pillInset
          anchors.bottomMargin: Style.bar.pillInset
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
