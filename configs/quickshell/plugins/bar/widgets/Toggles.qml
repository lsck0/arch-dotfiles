import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "toggles"


  property string text: "⚙ 0"
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
    // wait for exit; a detached run raced the refresh
    if (toggleProc.running) return
    toggleProc.command = [Paths.toggle("toggle-" + name + ".sh"), "toggle"]
    toggleProc.running = true
  }

  Process {
    id: toggleProc
    running: false
    onExited: { root.refresh(); root.refreshItems() }
  }

  Process {
    id: statusProc
    command: [Paths.toggle("status.sh")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var s = JSON.parse(text || "{}")
          root.text = s.text || "⚙ 0"
        } catch (e) {}
      }
    }
  }

  Process {
    id: itemsProc
    command: [Paths.barWidget("toggles-list.sh")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.items = JSON.parse(text || "[]") } catch (e) {}
      }
    }
  }

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
    onEntered: if (root.bar) root.bar.hoverOpen(root.moduleName)
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    onOpened: root.refreshItems()
    title: "TOGGLES"
    implicitWidth: Style.panelWidth.narrow + Style.shadowOffset
    implicitHeight: Math.min(Style.space(400), content.implicitHeight + padding * 2 + titleInset) + Style.shadowOffset

    Flickable {
      anchors.fill: parent
      // vertical only, inert while everything fits
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

        PanelSectionHeader {
          text: "SWITCHES" + (root.items.length > 0 ? " :: " + root.items.length : "")
        }

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
          text: "> LOADING..."
          color: Color.menu.text
          opacity: Style.emphasis.faint
          font.pixelSize: Style.font.body
          font.family: Style.font.family
          font.letterSpacing: Style.displayTracking
        }
      }
    }
  }
}
