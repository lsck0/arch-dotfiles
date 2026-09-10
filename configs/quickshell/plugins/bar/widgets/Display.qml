import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell. Monitor resolution/scale changes go
// through `hyprctl keyword monitor` (runtime-only, not persisted to
// hyprland_monitors.lua) so a bad choice is reversible with `hyprctl reload`
// rather than editing the actual config — deliberately cautious after the
// HDMI monitor debugging earlier this session.
BarWidget {
  id: root
  moduleName: "display"

  property int brightnessPct: 100
  property var monitors: []
  readonly property var fontChoices: ["0xProto Nerd Font", "JetBrainsMono Nerd Font", "FiraCode Nerd Font", "Hack Nerd Font"]
  readonly property var fontSizes: [12, 13, 14, 16, 18]

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refreshBrightness() {
    if (!brightnessProc.running) brightnessProc.running = true
  }

  function refreshMonitors() {
    if (!monitorsProc.running) monitorsProc.running = true
  }

  function setBrightness(pct) {
    pct = Math.max(1, Math.min(100, Math.round(pct)))
    Quickshell.execDetached(["brightnessctl", "-q", "set", pct + "%"])
    root.brightnessPct = pct
  }

  function openWallpaperPicker() {
    Quickshell.execDetached(Quickshell.env("HOME") + "/projects/arch-dotfiles/scripts/switch-wallpaper.sh")
  }

  function setFont(family) {
    Quickshell.execDetached(["bash", "-lc",
      "sed -i \"s/font-family = .*/font-family = " + family + "/\" ~/.config/ghostty/config; " +
      "sed -i 's/\"buffer_font_family\": \"[^\"]*\"/\"buffer_font_family\": \"" + family + "\"/;" +
      "s/\"ui_font_family\": \"[^\"]*\"/\"ui_font_family\": \"" + family + "\"/' ~/.config/zed/settings.json"])
  }

  function setFontSize(size) {
    Quickshell.execDetached(["bash", "-lc",
      "sed -i \"s/font-size = .*/font-size = " + size + "/\" ~/.config/ghostty/config; " +
      "sed -i 's/\"buffer_font_size\": [0-9]*/\"buffer_font_size\": " + size + "/;" +
      "s/\"ui_font_size\": [0-9]*/\"ui_font_size\": " + size + "/' ~/.config/zed/settings.json"])
  }

  function setMonitorScale(name, scale) {
    Quickshell.execDetached(["bash", "-lc", "hyprctl keyword monitor " + name + ",preferred,auto," + scale])
    refreshMonitors()
  }

  Process {
    id: brightnessProc
    command: ["brightnessctl", "-m", "info"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split(",")
        if (parts.length >= 4) {
          var pct = parseInt(parts[3].replace("%", ""), 10)
          if (!isNaN(pct)) root.brightnessPct = pct
        }
      }
    }
  }

  Process {
    id: monitorsProc
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.monitors = JSON.parse(text || "[]") } catch (e) {}
      }
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshBrightness()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍹"
    onEntered: { root.bar.hoverOpen(root.moduleName); root.refreshMonitors() }
    onExited: root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchors { top: true; right: true }
    margins { top: root.barSize + 4; right: 8 }
    implicitWidth: 360
    implicitHeight: content.implicitHeight + padding * 2

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.lg

      Text { text: "Brightness"; color: Color.menu.text; opacity: 0.6; font.pixelSize: Style.font.caption; font.family: Style.font.family }

      Rectangle {
        width: parent.width
        height: Style.space(20)
        radius: height / 2
        color: Util.alpha(Color.menu.text, 0.15)

        Rectangle {
          height: parent.height
          width: parent.width * root.brightnessPct / 100
          radius: height / 2
          color: Color.accent
        }

        MouseArea {
          anchors.fill: parent
          onPressed: function(mouse) { root.setBrightness(mouse.x / width * 100) }
          onPositionChanged: function(mouse) { if (pressed) root.setBrightness(mouse.x / width * 100) }
        }
      }

      Text { text: "Wallpaper"; color: Color.menu.text; opacity: 0.6; font.pixelSize: Style.font.caption; font.family: Style.font.family }

      Rectangle {
        width: parent.width
        height: Style.space(32)
        radius: Style.cornerRadius
        color: Util.alpha(Color.menu.text, 0.08)
        Text {
          anchors.centerIn: parent
          text: "Choose wallpaper…"
          color: Color.menu.text
          font.pixelSize: Style.font.body
          font.family: Style.font.family
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: { root.openWallpaperPicker(); root.bar.closePanel(root.moduleName) }
        }
      }

      Text { text: "Font"; color: Color.menu.text; opacity: 0.6; font.pixelSize: Style.font.caption; font.family: Style.font.family }

      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        Repeater {
          model: root.fontChoices
          Rectangle {
            required property string modelData
            width: fontLabel.implicitWidth + Style.spacing.md * 2
            height: Style.space(28)
            radius: Style.cornerRadius
            color: Style.fontFamily === modelData ? Color.menu.selectedBackground : Util.alpha(Color.menu.text, 0.08)
            Text {
              id: fontLabel
              anchors.centerIn: parent
              text: parent.modelData
              color: Color.menu.text
              font.pixelSize: Style.font.bodySmall
              font.family: Style.font.family
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setFont(parent.modelData)
            }
          }
        }
      }

      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        Repeater {
          model: root.fontSizes
          Rectangle {
            required property int modelData
            width: Style.space(34)
            height: Style.space(28)
            radius: Style.cornerRadius
            color: Util.alpha(Color.menu.text, 0.08)
            Text {
              anchors.centerIn: parent
              text: String(parent.modelData)
              color: Color.menu.text
              font.pixelSize: Style.font.bodySmall
              font.family: Style.font.family
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setFontSize(parent.modelData)
            }
          }
        }
      }

      Text { text: "Monitors"; color: Color.menu.text; opacity: 0.6; font.pixelSize: Style.font.caption; font.family: Style.font.family }

      Repeater {
        model: root.monitors
        Column {
          id: monitorRow
          required property var modelData
          width: content.width
          spacing: Style.spacing.xs

          Text {
            text: monitorRow.modelData.name + "  " + monitorRow.modelData.width + "x" + monitorRow.modelData.height + "@" + Math.round(monitorRow.modelData.refreshRate) + "Hz  " + monitorRow.modelData.scale.toFixed(2) + "x"
            color: Color.menu.text
            font.pixelSize: Style.font.bodySmall
            font.family: Style.font.family
          }

          Flow {
            width: parent.width
            spacing: Style.spacing.xs
            Repeater {
              model: [1, 1.25, 1.5, 1.666667, 2]
              Rectangle {
                required property real modelData
                width: Style.space(40)
                height: Style.space(22)
                radius: Style.cornerRadius
                color: Util.alpha(Color.menu.text, 0.08)
                Text {
                  anchors.centerIn: parent
                  text: parent.modelData + "x"
                  color: Color.menu.text
                  font.pixelSize: Style.font.caption
                  font.family: Style.font.family
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setMonitorScale(monitorRow.modelData.name, parent.modelData)
                }
              }
            }
          }
        }
      }
    }
  }
}
