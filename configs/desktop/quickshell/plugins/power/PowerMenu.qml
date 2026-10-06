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
    { label: "Shutdown", hotkey: "S", icon: "\u{f011}", cmd: ["systemctl", "poweroff"] },
    { label: "Reboot", hotkey: "R", icon: "\u{f0709}", cmd: ["systemctl", "reboot"] },
    { label: "Firmware", hotkey: "F", icon: "\u{f0493}", cmd: ["systemctl", "reboot", "--firmware-setup"] }
  ]

  function open() {
    root.selectedIndex = 0
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function activate(index) {
    var action = root.actions[index]
    if (!action) return
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

  PanelWindow {
    visible: root.opened
    color: "transparent"
    WlrLayershell.namespace: "quickshell-powermenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
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

      Column {
        anchors.centerIn: parent
        spacing: Style.spacing.huge

        Item {
          width: actionRow.width
          implicitHeight: titleRow.implicitHeight + Style.spacing.sm + titleRule.height
          height: implicitHeight

          Row {
            id: titleRow
            anchors.left: parent.left
            anchors.top: parent.top
            spacing: Style.spacing.sm

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: ">"
              color: Color.accent
              opacity: Style.emphasis.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.title
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "SESSION"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              font.letterSpacing: Style.headerTracking
              layer.enabled: Style.fx.glow > 0
              layer.effect: Glow {}
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "_"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              layer.enabled: Style.fx.glow > 0
              layer.effect: Glow {}
              SequentialAnimation on opacity {
                running: root.opened
                loops: Animation.Infinite
                PropertyAnimation { to: 1; duration: 0 }
                PauseAnimation { duration: 530 }
                PropertyAnimation { to: 0; duration: 0 }
                PauseAnimation { duration: 530 }
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              visible: root.userName.length > 0
              text: "@" + root.userName
              color: Color.menu.text
              opacity: Style.emphasis.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.title
            }
          }

          // decorative, non-interactive
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: titleRow.verticalCenter
            textFormat: Text.PlainText
            text: "[- o x]"
            color: Color.accent
            opacity: Style.emphasis.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.letterSpacing: Style.headerTracking
          }

          Rectangle {
            id: titleRule
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titleRow.bottom
            anchors.topMargin: Style.spacing.sm
            height: Math.max(1, Style.space(1))
            color: Util.alpha(Color.accent, 0.8)
          }
        }

        Row {
          id: actionRow
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.lg

          Repeater {
            model: root.actions

            BorderSurface {
              id: tile
              required property var modelData
              required property int index
              readonly property bool selected: index === root.selectedIndex
              readonly property color tint: Color.accent

              width: Style.space(132)
              height: Style.space(132)
              radius: Style.cornerRadius
              // tint onto the opaque surface so the scrim does not read through
              color: Qt.tint(Color.menu.background, selected ? Style.selectedFillFor(Color.menu.text, tint) : Style.normalFillFor(Color.menu.text, tint))
              borderSpec: Border.controlSpec(selected ? "selected" : "normal", Color.menu.text, tint)

              Column {
                anchors.centerIn: parent
                spacing: Style.spacing.sm

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
                anchors.topMargin: Style.spacing.sm
                anchors.leftMargin: Style.spacing.sm
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
                onEntered: root.selectedIndex = tile.index
                onClicked: root.activate(tile.index)
              }
            }
          }
        }
      }

      Scanlines { flicker: false }
    }
  }
}
