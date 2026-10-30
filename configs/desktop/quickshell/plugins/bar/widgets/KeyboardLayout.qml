import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import "KeyboardLayoutModel.js" as KeyboardLayoutModel

BarWidget {
  id: root
  moduleName: "keyboard-layout"
  barPriority: 45

  property string layoutFull: ""
  property string keyboardName: ""
  property string typedKeyboardName: ""
  property bool multipleLayouts: true
  property var layoutBriefs: ({})
  readonly property string layoutLabel: KeyboardLayoutModel.shortLabel(layoutFull, layoutBriefs)

  property bool refreshPending: false

  function refresh() {
    if (queryProc.running) {
      refreshPending = true
      return
    }

    refreshPending = false
    queryProc.running = true
  }

  function cycleLayout() {
    if (!root.keyboardName) return
    Quickshell.execDetached(["hyprctl", "switchxkblayout", root.keyboardName, "next"])
    refreshTimer.restart()
  }

  Component.onCompleted: {
    briefsProc.running = true
    refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      if (name === "activelayout") {
        const named = KeyboardLayoutModel.eventKeyboardName(event)
        if (named) root.typedKeyboardName = named
      }

      if (name.indexOf("activelayout") !== -1 || name === "configreloaded") root.refresh()
    }
  }

  JsonProcess {
    id: queryProc
    command: ["hyprctl", "-j", "devices"]
    onRunningChanged: {
      if (running) {
        stallTimer.restart()
        return
      }

      stallTimer.stop()
      if (root.refreshPending) root.refresh()
    }
    onParsed: function(devices) {
      const listed = devices ? devices.keyboards : null
      if (!Array.isArray(listed)) return

      const typed = listed.filter(k => KeyboardLayoutModel.isTypedKeyboard(k.name))
      const kb = KeyboardLayoutModel.selectKeyboard(typed, root.typedKeyboardName)
      if (!kb || !kb.active_keymap) {
        if (typed.length === 0) {
          root.layoutFull = ""
          root.keyboardName = ""
        }
        return
      }

      root.keyboardName = String(kb.name || "")
      root.multipleLayouts = kb.layout === undefined || String(kb.layout).indexOf(",") !== -1
      root.layoutFull = kb.active_keymap
    }
  }

  Process {
    id: briefsProc
    command: ["xkbcli", "list", "--load-exotic"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.layoutBriefs = KeyboardLayoutModel.layoutBriefs(text)
    }
  }

  Timer {
    id: refreshTimer
    interval: 600
    onTriggered: root.refresh()
  }

  Timer {
    id: stallTimer
    interval: 5000
    onTriggered: {
      queryProc.running = false
      refreshTimer.restart()
    }
  }

  visible: layoutLabel !== "" && multipleLayouts
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.layoutLabel
    fontSize: Style.font.caption
    horizontalMargin: Style.spacing.xs
    tooltipText: root.layoutFull
    onPressed: function() { root.cycleLayout() }
  }
}
