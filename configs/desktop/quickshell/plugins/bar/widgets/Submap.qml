import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// the active Hyprland submap as a chip, from the `submap` event and one `hyprctl submap` at load; its plain letter keys
// come from one `hyprctl binds` per change
BarWidget {
  id: root
  moduleName: "submap"
  barPriority: 95

  property string submap: ""
  property string keys: ""

  function keysOf(binds) {
    var letters = []
    for (const bind of binds || []) {
      if (bind.submap !== root.submap || bind.modmask !== 0 || bind.catch_all) continue
      const key = String(bind.key)
      if (key.length === 1 && letters.indexOf(key) === -1) letters.push(key)
    }
    return letters.sort().join(" ")
  }

  function enter(name) {
    root.submap = name === "default" ? "" : name
    root.keys = ""
    if (root.submap !== "") bindsProc.run()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && event.name === "submap") root.enter(String(event.data || ""))
    }
  }

  JsonProcess {
    id: currentProc
    command: ["hyprctl", "-j", "submap"]
    onParsed: function(name) { root.enter(String(name || "")) }
  }
  Component.onCompleted: currentProc.run()

  JsonProcess {
    id: bindsProc
    command: ["hyprctl", "-j", "binds"]
    onParsed: function(binds) { root.keys = root.keysOf(binds) }
  }

  visible: submap !== ""
  implicitWidth: chip.width
  implicitHeight: Style.bar.sizeHorizontal

  Rectangle {
    id: chip
    anchors.verticalCenter: parent.verticalCenter
    width: row.implicitWidth + Style.spacing.sm * 2
    height: parent.height - Style.bar.pillInset * 2
    radius: Style.shape.data
    color: "transparent"
    border.width: Style.normalBorderWidth
    border.color: Util.alpha(Colors.accent, Style.hoverBorderAlpha)

    Row {
      id: row
      anchors.centerIn: parent
      spacing: Style.spacing.sm

      Label {
        anchors.verticalCenter: parent.verticalCenter
        text: root.submap.toUpperCase()
        color: Colors.accentText
        caption: true
        font.bold: true
        font.letterSpacing: Style.labelTracking
      }

      Label {
        visible: root.keys !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.keys
        color: Colors.bar.text
        caption: true
      }
    }
  }
}
