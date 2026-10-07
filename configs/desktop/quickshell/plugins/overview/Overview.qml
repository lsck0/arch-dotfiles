import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// one overview per monitor: its workspaces as tiles, each window a ScreencopyView at its scaled hyprland geometry
Item {
  id: root

  property bool opened: false

  // tiles per row and the widest tile, the card shrinks below that to fit the output
  readonly property int maxColumns: 4
  readonly property int maxTileWidth: Style.space(360)
  // share of the output the card may take
  readonly property real screenShare: 0.9

  function workspacesOn(monitorName) {
    var values = Hyprland.workspaces.values
    var out = []
    for (var i = 0; i < values.length; i++) {
      var w = values[i]
      if (w.id > 0 && w.monitor && String(w.monitor.name) === monitorName) out.push(w)
    }
    out.sort(function(a, b) { return a.id - b.id })
    return out
  }

  function open() {
    // window geometry lives in lastIpcObject, stale until refreshed
    Hyprland.refreshToplevels()
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function focusAndClose(id) {
    Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
    root.close()
  }

  IpcHandler {
    target: "overview"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
  }

  Variants {
    model: Quickshell.screens

    OverlayCard {
      id: panel
      required property var modelData
      screen: modelData

      readonly property string monitorName: String(modelData.name)
      readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
      // only the focused output's card takes keys; the others are pointer-only
      readonly property bool focusedOutput: Hyprland.focusedMonitor !== null && String(Hyprland.focusedMonitor.name) === monitorName

      // live while open, frozen while the card closes so the grid does not collapse mid-exit
      property var workspaces: []
      Binding { target: panel; property: "workspaces"; value: root.workspacesOn(panel.monitorName); when: root.opened; restoreMode: Binding.RestoreNone }
      property int selectedIndex: 0

      readonly property int columns: Math.min(root.maxColumns, Math.max(1, workspaces.length))
      readonly property int rowCount: Math.ceil(Math.max(1, workspaces.length) / columns)
      // logical output size, the space hyprland window geometry lives in
      readonly property real outW: Math.max(1, modelData.width)
      readonly property real outH: Math.max(1, modelData.height)
      readonly property real tileWidth: Math.max(Style.space(120), Math.min(root.maxTileWidth,
        (outW * root.screenShare - chromeWidth - Style.spacing.xl * 2 - grid.spacing * (columns - 1)) / columns))
      readonly property real tileHeight: Math.round(tileWidth * outH / outW)

      open: root.opened
      keyboard: focusedOutput
      name: "overview"
      title: "workspaces"
      suffix: monitorName + " [" + String(workspaces.length) + "]"
      hints: [["< > ^ v", "select"], ["ENTER", "go"], ["1-0", "direct"], ["ESC", "close"]]
      cardWidth: grid.implicitWidth + Style.spacing.xl * 2 + chromeWidth
      cardHeight: grid.implicitHeight + Style.spacing.xl * 2 + chromeHeight
      onDismissed: root.close()

      onOpenChanged: {
        if (!open) return
        var active = hyprMonitor && hyprMonitor.activeWorkspace ? hyprMonitor.activeWorkspace.id : -1
        var list = root.workspacesOn(monitorName)
        selectedIndex = 0
        for (var i = 0; i < list.length; i++) if (list[i].id === active) selectedIndex = i
        if (focusedOutput) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      }

      function move(delta) {
        panel.selectedIndex = Math.max(0, Math.min(panel.workspaces.length - 1, panel.selectedIndex + delta))
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var list = panel.workspaces
          if (event.key === Qt.Key_Escape) root.close()
          else if (event.key === Qt.Key_Left) panel.move(-1)
          else if (event.key === Qt.Key_Right) panel.move(1)
          else if (event.key === Qt.Key_Up) panel.move(-panel.columns)
          else if (event.key === Qt.Key_Down) panel.move(panel.columns)
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (list.length > 0) root.focusAndClose(list[panel.selectedIndex].id)
          }
          // unrestricted, matching super+n on empty workspaces
          else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) root.focusAndClose(event.key - Qt.Key_0)
          else if (event.key === Qt.Key_0) root.focusAndClose(10)
          else return
          event.accepted = true
        }
      }

      Grid {
        id: grid
        anchors.centerIn: parent
        columns: panel.columns
        spacing: Style.spacing.md

        Repeater {
          model: panel.workspaces

          BorderSurface {
            id: tile
            required property var modelData
            required property int index
            readonly property var toplevels: modelData.toplevels.values
            readonly property bool focused: panel.hyprMonitor !== null && panel.hyprMonitor.activeWorkspace === modelData
            readonly property bool selected: index === panel.selectedIndex
            // logical px to tile px
            readonly property real k: width / panel.outW

            width: panel.tileWidth
            height: panel.tileHeight
            radius: Style.shape.data
            opacity: panel.boot.rowOpacity(index)
            color: Util.alpha(Color.background, Style.translucency.overlay)
            borderSpec: Border.controlSpec(selected ? "selected" : "normal", Color.menu.text, Color.accent)
            clip: true

            Repeater {
              model: tile.toplevels

              Item {
                id: win
                required property var modelData
                readonly property var ipc: modelData.lastIpcObject || ({})
                readonly property var at: ipc.at || [panel.modelData.x, panel.modelData.y]
                readonly property var size: ipc.size || [panel.outW, panel.outH]

                x: (at[0] - panel.modelData.x) * tile.k
                y: (at[1] - panel.modelData.y) * tile.k
                width: Math.max(1, size[0] * tile.k)
                height: Math.max(1, size[1] * tile.k)
                // floating and fullscreen windows sit above the tiled layer, as on screen
                z: ipc.fullscreen ? 2 : ipc.floating ? 1 : 0

                Rectangle {
                  anchors.fill: parent
                  color: Color.surface
                  border.width: Style.surface.borderWidth
                  border.color: Util.alpha(Color.foreground, Style.normalBorderAlpha)
                }

                // captures only while the overview is open; the selected tile stays live
                ScreencopyView {
                  id: capture
                  anchors.fill: parent
                  captureSource: root.opened && win.modelData.wayland ? win.modelData.wayland : null
                  live: root.opened && tile.selected
                  paintCursor: false
                }

                Text {
                  visible: !capture.hasContent
                  anchors.centerIn: parent
                  width: parent.width - Style.spacing.xs * 2
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: win.modelData.wayland ? String(win.modelData.wayland.appId || "--") : "--"
                  color: Color.menu.text
                  opacity: Style.emphasis.faint
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: tile.toplevels.length === 0
              anchors.centerIn: parent
              text: "--"
              color: Color.menu.text
              opacity: Style.emphasis.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            // dims the rest so the selected tile reads first
            Rectangle {
              anchors.fill: parent
              z: 3
              color: Util.alpha(Color.background, tile.selected ? 0 : Style.translucency.scrim * 0.75)
              Behavior on color { ColorAnimation { duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }
            }

            Rectangle {
              z: 4
              anchors.left: parent.left
              anchors.top: parent.top
              width: label.implicitWidth + Style.spacing.sm * 2
              height: label.implicitHeight + Style.spacing.xs * 2
              color: Color.overlayFill

              Text {
                id: label
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "[" + (tile.modelData.id === 10 ? "0" : String(tile.modelData.id)) + "]"
                  + (tile.focused ? " *" : "") + (tile.toplevels.length > 0 ? " " + tile.toplevels.length : "")
                color: tile.selected ? Color.accent : Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.letterSpacing: Style.headerTracking
              }
            }

            HudFrame { shown: tile.selected; z: 5 }

            MouseArea {
              anchors.fill: parent
              z: 6
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: panel.selectedIndex = tile.index
              onClicked: root.focusAndClose(tile.modelData.id)
            }
          }
        }
      }
    }
  }
}
