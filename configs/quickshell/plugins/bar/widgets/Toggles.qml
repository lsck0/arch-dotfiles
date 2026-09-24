import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell.
BarWidget {
  id: root
  moduleName: "toggles"

  readonly property string toggleDir: Paths.toggles
  readonly property string scriptDir: Paths.barWidgets

  property string text: "⚙ 0"
  property string tooltip: ""
  property var items: []

  implicitWidth: label.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: mouseArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function refreshItems() {
    if (!itemsProc.running) itemsProc.running = true
  }

  function toggleItem(name) {
    // Same fix as Notifications.qml's toggleDnd(): wait for the toggle script to actually exit before refreshing, instead of firing it detached and refreshing on the next event-loop tick (which reliably beat the script to the finish and re-displayed the pre-toggle state).
    if (toggleProc.running) return
    toggleProc.command = [root.toggleDir + "/toggle-" + name + ".sh", "toggle"]
    toggleProc.running = true
  }

  Process {
    id: toggleProc
    running: false
    onExited: { root.refresh(); root.refreshItems() }
  }

  Process {
    id: statusProc
    command: [root.toggleDir + "/status.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var s = JSON.parse(text || "{}")
          root.text = s.text || "⚙ 0"
          root.tooltip = s.tooltip || ""
        } catch (e) {}
      }
    }
  }

  Process {
    id: itemsProc
    command: [root.scriptDir + "/toggles-list.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.items = JSON.parse(text || "[]") } catch (e) {}
      }
    }
  }

  // Was 5000ms.
  Timer {
    interval: 20000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.text
    color: root.bar ? root.bar.barForeground : Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.bar.hoverOpen(root.moduleName)
    onExited: root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    onOpened: root.refreshItems()
    implicitWidth: Style.panelWidth.narrow + Style.shadowOffset
    implicitHeight: Math.min(Style.space(400), content.implicitHeight + padding * 2) + Style.shadowOffset

    Flickable {
      id: togglesFlick
      anchors.fill: parent
      // Same as the notification history list: bound to the vertical axis and inert while everything fits, so a horizontal drag cannot slide the toggle rows off the card.
      contentWidth: width
      contentHeight: content.implicitHeight
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds
      clip: true

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.xs

        // Ui/Toggle.qml floors each row at 54px — ten toggles is ~540px, taller than most screens want popping open on hover.
        Repeater {
          model: root.items
          Toggle {
            required property var modelData
            width: content.width
            label: modelData.label
            checked: modelData.on
            titleSize: Style.font.body
            onClicked: root.toggleItem(modelData.name)
          }
        }

        Text {
          visible: root.items.length === 0
          text: "Loading…"
          color: Color.menu.text
          opacity: Style.emphasis.faint
          font.pixelSize: Style.font.body
          font.family: Style.font.family
        }
      }
    }
  }
}
