pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property bool opened: false

  readonly property int maxColumns: 4
  readonly property int maxTileWidth: Style.space(360)
  readonly property real screenShare: 0.9

  function workspacesAll() {
    var values = Hyprland.workspaces.values
    var out = []
    for (let i = 0; i < values.length; i++) if (values[i].id > 0 && values[i].monitor) out.push(values[i])
    out.sort(function (a, b) { return a.id - b.id })
    return out
  }

  function screenFor(monitor) {
    var name = monitor ? String(monitor.name) : ""
    return Array.from(Quickshell.screens).find(function (s) { return String(s.name) === name }) || null
  }

  property var workspaces: []
  Binding { target: root; property: "workspaces"; value: root.workspacesAll(); when: root.opened; restoreMode: Binding.RestoreNone }
  property int selectedIndex: 0
  readonly property bool multiMonitor: Quickshell.screens.length > 1

  function open() {
    // window geometry lives in lastIpcObject, stale until refreshed
    Hyprland.refreshToplevels()
    var focused = Hyprland.focusedMonitor
    panel.screen = root.screenFor(focused)
    var list = root.workspacesAll()
    var active = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    root.selectedIndex = Math.max(0, list.findIndex(function (w) { return w.id === active }))
    panel.lastPointer = Qt.point(NaN, NaN)
    root.opened = true
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
    // hyprland's binds beat the overlay's keyboard focus: the submap turns held-mod tab/return into cycle and go
    Hyprland.dispatch("hl.dsp.submap(\"overview\")")
  }

  function close() {
    if (!root.opened) return
    root.opened = false
    Hyprland.dispatch("hl.dsp.submap(\"reset\")")
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function move(delta) {
    root.selectedIndex = Math.max(0, Math.min(root.workspaces.length - 1, root.selectedIndex + delta))
  }

  function cycle(delta) {
    var n = root.workspaces.length
    if (n > 0) root.selectedIndex = ((root.selectedIndex + delta) % n + n) % n
  }

  function commit() {
    if (root.workspaces.length > 0) root.focusAndClose(root.workspaces[root.selectedIndex].id)
  }

  // release the overlay first: its focus release refocuses the old window, which would drag the switch back
  property string pendingWorkspace: ""

  function focusAndClose(id) {
    root.pendingWorkspace = String(id)
    root.close()
    switchDelay.restart()
  }

  Timer {
    id: switchDelay
    // past the layer's keyboard release, which lands on its next commit
    interval: 80
    onTriggered: {
      if (root.pendingWorkspace !== "") Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + root.pendingWorkspace + "\" })")
      root.pendingWorkspace = ""
    }
  }

  IpcHandler {
    target: "overview"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
    function next(): string { if (root.opened) root.cycle(1); else root.open(); return "ok" }
    function prev(): string { if (root.opened) root.cycle(-1); else root.open(); return "ok" }
    function commit(): string { if (root.opened) root.commit(); return "ok" }
  }

  OverlayCard {
    id: panel

    property point lastPointer: Qt.point(NaN, NaN)

    readonly property int columns: Math.min(root.maxColumns, Math.max(1, root.workspaces.length))
    readonly property int rowCount: Math.ceil(Math.max(1, root.workspaces.length) / columns)
    readonly property real aspectMax: {
      var out = 0
      for (let i = 0; i < root.workspaces.length; i++) {
        let s = root.screenFor(root.workspaces[i].monitor)
        if (s) out = Math.max(out, s.height / Math.max(1, s.width))
      }
      return out > 0 ? out : 9 / 16
    }
    readonly property real tileWidth: {
      var budgetW = (width * root.screenShare - chromeWidth - Style.spacing.xl * 2 - grid.spacing * (columns - 1)) / columns
      var budgetH = (height * root.screenShare - chromeHeight - Style.spacing.xl * 2 - grid.spacing * (rowCount - 1)) / rowCount
      return Math.max(Style.space(120), Math.min(root.maxTileWidth, budgetW, budgetH / aspectMax))
    }

    open: root.opened
    name: "overview"
    title: "workspaces"
    suffix: "[" + String(root.workspaces.length) + "]"
    hints: [["TAB < > ^ v", "select"], ["ENTER", "go"], ["1-0", "direct"], ["ESC", "close"]]
    cardWidth: grid.implicitWidth + Style.spacing.xl * 2 + chromeWidth
    cardHeight: grid.implicitHeight + Style.spacing.xl * 2 + chromeHeight
    onDismissed: root.close()

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) root.close()
        else if (event.key === Qt.Key_Left) root.move(-1)
        else if (event.key === Qt.Key_Right) root.move(1)
        else if (event.key === Qt.Key_Up) root.move(-panel.columns)
        else if (event.key === Qt.Key_Down) root.move(panel.columns)
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.commit()
        else if (event.key === Qt.Key_Tab) root.cycle(1)
        else if (event.key === Qt.Key_Backtab) root.cycle(-1)
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
      verticalItemAlignment: Grid.AlignVCenter

      Repeater {
        model: root.workspaces

        BorderSurface {
          id: tile
          required property var modelData
          required property int index
          readonly property var toplevels: modelData.toplevels.values
          readonly property var output: root.screenFor(modelData.monitor)
          readonly property real outX: output ? output.x : 0
          readonly property real outY: output ? output.y : 0
          readonly property real outW: Math.max(1, output ? output.width : panel.width)
          readonly property real outH: Math.max(1, output ? output.height : panel.height)
          readonly property bool selected: index === root.selectedIndex
          readonly property real k: width / outW

          width: panel.tileWidth
          height: Math.round(panel.tileWidth * outH / outW)
          radius: Style.shape.data
          opacity: panel.boot.rowOpacity(index)
          color: Util.alpha(Colors.background, Style.translucency.overlay)
          borderSpec: Border.controlSpec(selected ? "selected" : "normal", Colors.menu.text, Colors.accent)
          clip: true

          Repeater {
            model: tile.toplevels

            Item {
              id: win
              required property var modelData
              readonly property var ipc: modelData.lastIpcObject || ({})
              readonly property var at: ipc.at || [tile.outX, tile.outY]
              readonly property var size: ipc.size || [tile.outW, tile.outH]

              x: (at[0] - tile.outX) * tile.k
              y: (at[1] - tile.outY) * tile.k
              width: Math.max(1, size[0] * tile.k)
              height: Math.max(1, size[1] * tile.k)
              z: ipc.fullscreen ? 2 : ipc.floating ? 1 : 0

              Rectangle {
                anchors.fill: parent
                color: Colors.surface
                border.width: Style.surface.borderWidth
                border.color: Util.alpha(Colors.foreground, Style.normalBorderAlpha)
              }

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
                color: Colors.menu.text
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
            color: Colors.menu.text
            opacity: Style.emphasis.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Rectangle {
            anchors.fill: parent
            z: 3
            color: Util.alpha(Colors.background, tile.selected ? 0 : Style.translucency.scrim * 0.75)
            Behavior on color { ColorAnimation { duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }
          }

          Rectangle {
            z: 4
            anchors.left: parent.left
            anchors.top: parent.top
            width: label.implicitWidth + Style.spacing.sm * 2
            height: label.implicitHeight + Style.spacing.xs * 2
            color: Colors.overlayFill

            Text {
              id: label
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "[" + (tile.modelData.id === 10 ? "0" : String(tile.modelData.id)) + "]"
                + (root.multiMonitor ? " " + String(tile.modelData.monitor.name) : "")
                + (tile.modelData.active ? " *" : "") + (tile.toplevels.length > 0 ? " " + tile.toplevels.length : "")
              color: tile.selected ? Colors.accent : tile.modelData.focused ? Colors.menu.selectedText : Colors.menu.text
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
            // real motion only, else a tile under a resting cursor steals the keyboard's selection
            onPositionChanged: function (mouse) {
              var p = mapToGlobal(mouse.x, mouse.y)
              var moved = !isNaN(panel.lastPointer.x)
                && (Math.abs(p.x - panel.lastPointer.x) >= 1 || Math.abs(p.y - panel.lastPointer.y) >= 1)
              panel.lastPointer = p
              if (moved) root.selectedIndex = tile.index
            }
            onClicked: root.focusAndClose(tile.modelData.id)
          }
        }
      }
    }
  }
}
