import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property bool opened: false
  property int selectedIndex: 0
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""
  readonly property var actions: [
    { label: "Lock", hotkey: "L", icon: "\u{f023}", cmd: ["loginctl", "lock-session"] },
    // terminate the session directly instead of asking hyprland to exit
    { label: "Exit", hotkey: "E", icon: "\u{f08b}", cmd: ["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\""] },
    { label: "Suspend", hotkey: "H", icon: "\u{f04b2}", cmd: ["systemctl", "suspend"] },
    // these end the session for good, so they ask first
    { label: "Shutdown", hotkey: "S", icon: "\u{f011}", cmd: ["systemctl", "poweroff"], confirm: true },
    { label: "Reboot", hotkey: "R", icon: "\u{f0709}", cmd: ["systemctl", "reboot"], confirm: true },
    { label: "Firmware", hotkey: "F", icon: "\u{f0493}", cmd: ["systemctl", "reboot", "--firmware-setup"], confirm: true }
  ]
  // index awaiting [Y/n], -1 when none
  property int pendingIndex: -1
  readonly property var pendingAction: pendingIndex >= 0 ? actions[pendingIndex] : null

  function open() {
    root.selectedIndex = 0
    root.pendingIndex = -1
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.pendingIndex = -1
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function activate(index) {
    var action = root.actions[index]
    if (!action) return
    if (action.confirm && root.pendingIndex !== index) {
      root.selectedIndex = index
      root.pendingIndex = index
      return
    }
    Quickshell.execDetached(action.cmd)
    root.close()
  }

  function hotkeyIndex(key) {
    var letter = String.fromCharCode(key).toUpperCase()
    for (var i = 0; i < root.actions.length; i++)
      if (root.actions[i].hotkey === letter) return i
    return -1
  }

  IpcHandler {
    target: "powermenu"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
  }

  OverlayCard {
    id: panel
    open: root.opened
    name: "powermenu"
    title: "session"
    suffix: root.userName.length > 0 ? "@" + root.userName : ""
    hints: root.pendingAction
      ? [["Y ENTER", "confirm"], ["N ESC", "cancel"]]
      : [["< >", "select"], ["ENTER", "run"], ["L E H S R F", "direct"], ["ESC", "close"]]
    cardWidth: actionRow.implicitWidth + chromeWidth
    cardHeight: actionRow.implicitHeight + confirmLine.height + Style.spacing.sm + chromeHeight
    onDismissed: root.close()

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        // confirm line: Y or Enter runs, anything else cancels; the key is swallowed either way
        if (root.pendingAction) {
          if (event.key === Qt.Key_Y || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            root.activate(root.pendingIndex)
          else
            root.pendingIndex = -1
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Left) {
          root.selectedIndex = Math.max(0, root.selectedIndex - 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right) {
          root.selectedIndex = Math.min(root.actions.length - 1, root.selectedIndex + 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activate(root.selectedIndex)
          event.accepted = true
        } else {
          var index = root.hotkeyIndex(event.key)
          if (index >= 0) {
            root.activate(index)
            event.accepted = true
          }
        }
      }
    }

    Row {
      id: actionRow
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      spacing: Style.spacing.sm

      Repeater {
        model: root.actions

        BorderSurface {
          id: tile
          required property var modelData
          required property int index
          opacity: panel.boot.rowOpacity(index)
          readonly property bool selected: index === root.selectedIndex
          readonly property color tint: root.pendingIndex === index ? Color.urgent : Color.accent

          width: Style.space(132)
          height: Style.space(132)
          radius: Style.shape.data
          color: selected ? Style.selectedFillFor(Color.menu.text, tint) : Style.normalFillFor(Color.menu.text, tint)
          borderSpec: Border.controlSpec(selected ? "selected" : "normal", Color.menu.text, tint)

          Column {
            anchors.centerIn: parent
            spacing: Style.spacing.xs

            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              text: tile.modelData.icon
              color: tile.selected ? tile.tint : Color.menu.text
              font.family: Style.font.iconFamily
              font.pixelSize: Style.font.displayLarge
              layer.enabled: tile.selected && Style.fx.glow > 0
              layer.effect: Glow {}
            }

            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              text: tile.modelData.label
              color: tile.selected ? tile.tint : Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.capitalization: Font.AllUppercase
              font.letterSpacing: Style.headerTracking
            }
          }

          Text {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.topMargin: Style.spacing.xs
            anchors.leftMargin: Style.spacing.xs
            textFormat: Text.PlainText
            text: "[" + tile.modelData.hotkey + "]"
            color: tile.selected ? tile.tint : Color.menu.text
            opacity: tile.selected ? Style.emphasis.strong : Style.emphasis.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: Style.headerTracking
          }

          HudFrame { shown: tile.selected }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: if (!root.pendingAction) root.selectedIndex = tile.index
            onClicked: root.activate(tile.index)
          }
        }
      }
    }

    // `> SHUTDOWN? [Y/n]` under the tiles, blank when nothing waits
    Text {
      id: confirmLine
      anchors.top: actionRow.bottom
      anchors.topMargin: Style.spacing.sm
      anchors.left: actionRow.left
      height: Style.font.body + Style.spacing.xs * 2
      verticalAlignment: Text.AlignVCenter
      textFormat: Text.PlainText
      text: root.pendingAction ? "> " + root.pendingAction.label.toUpperCase() + "? [Y/n]" : ""
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
      font.letterSpacing: Style.headerTracking
    }
  }
}
