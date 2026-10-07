import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "ReminderFlowModel.js" as ReminderFlowModel

Item {
  id: root

  property bool opened: false
  property string step: "minutes"
  property string minutes: ""
  property string filterText: ""

  readonly property var pomo: TimerState.pomo
  readonly property var reminders: TimerState.reminders

  readonly property string reminderScript: Paths.script("reminder.sh")
  readonly property string pomodoroScript: Paths.script("pomodoro.sh")
  readonly property string notifyScript: Paths.dotfiles + "/scripts/lib/notification-send.sh"

  readonly property string promptText: step === "message"
    ? "Message for the " + minutes + " min reminder..."
    : "Remind me in ... minutes"

  function open() {
    root.opened = true
    root.step = "minutes"
    root.minutes = ""
    root.filterText = ""
    TimerState.reload()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function run(argv) {
    Quickshell.execDetached(argv)
    TimerState.reload()
  }

  function remindIn(minutes, message) {
    run([root.reminderScript].concat(ReminderFlowModel.reminderArgs(minutes, message)))
  }

  function submit() {
    if (root.step === "minutes") {
      if (!root.filterText.trim()) return
      var valid = ReminderFlowModel.validMinutes(root.filterText)
      if (!valid) {
        Quickshell.execDetached([root.notifyScript, "Invalid reminder", "Enter the number of minutes"])
        return
      }
      root.minutes = valid
      root.step = "message"
      root.filterText = ""
      return
    }
    root.remindIn(root.minutes, root.filterText)
    root.step = "minutes"
    root.minutes = ""
    root.filterText = ""
  }

  function phaseLabel() {
    if (!pomo.running) return "Ready"
    if (pomo.paused) return "Paused"
    return pomo.phase === "work" ? "Focus" : pomo.phase === "long" ? "Long break" : "Break"
  }

  // the singleton ticks the countdowns only while the overlay is open
  Binding { target: TimerState; property: "overlayOpen"; value: root.opened }

  OverlayCard {
    id: panel
    open: root.opened
    name: "reminders"
    title: "reminders"
    prompt: true
    query: root.filterText
    placeholder: root.promptText
    hints: root.step === "message"
      ? [["ENTER", "set"], ["ESC", "back"]]
      : [["0-9", "minutes"], ["ENTER", "set"], ["ESC", "close"]]
    cardWidth: Style.space(560)
    cardHeight: content.implicitHeight + chromeHeight
    onDismissed: root.close()

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (root.filterText) root.filterText = ""
          else if (root.step === "message") root.step = "minutes"
          else root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Backspace) {
          root.filterText = root.filterText.slice(0, -1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.submit()
          event.accepted = true
        } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
          // minutes step takes digits only
          if (root.step === "message" || /[0-9]/.test(event.text)) root.filterText += event.text
          event.accepted = true
        }
      }
    }

    Column {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.spacing.sm

      Row {
        id: chips
        width: parent.width
        spacing: Style.spacing.xs
        readonly property var presets: [5, 10, 15, 30, 45, 60]

        Repeater {
          model: chips.presets
          Chip {
            required property int modelData
            width: (chips.width - chips.spacing * (chips.presets.length - 1)) / chips.presets.length
            text: modelData + " min"
            onClicked: root.remindIn(String(modelData), "")
          }
        }
      }

      PanelSeparator {}

      Column {
        width: parent.width
        spacing: Style.spacing.xs

        PanelSectionHeader { text: "Reminders" }

        Text {
          visible: root.reminders.length === 0
          textFormat: Text.PlainText
          text: "> NOTHING HERE"
          color: Color.menu.text
          opacity: Style.emphasis.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Repeater {
          model: root.reminders
          delegate: Item {
            id: reminderRow
            required property var modelData
            width: parent.width
            height: Style.row.list

            Rectangle {
              anchors.fill: parent
              anchors.leftMargin: -Style.spacing.xs
              anchors.rightMargin: -Style.spacing.xs
              radius: Style.shape.data
              color: rowHover.hovered ? Style.hoverFill : "transparent"
            }
            HoverHandler { id: rowHover }

            Text {
              id: bell
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "\u{f009c}" // md-bell_outline
              color: Color.accent
              font.family: Style.font.iconFamily
              font.pixelSize: Style.font.icon
            }
            Text {
              anchors.left: bell.right
              anchors.leftMargin: Style.spacing.sm
              anchors.right: when.left
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: reminderRow.modelData.label || ""
              color: Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
            Row {
              id: when
              anchors.right: cancel.left
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs
              Text {
                textFormat: Text.PlainText
                text: "in " + (reminderRow.modelData.remaining || "")
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              Text {
                textFormat: Text.PlainText
                text: reminderRow.modelData.atTime || ""
                color: Color.menu.text
                opacity: Style.emphasis.faint
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }
            PanelActionButton {
              id: cancel
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "\u{f0156}" // md-close
              tooltipText: "Cancel reminder"
              foreground: Color.menu.text
              onClicked: root.run([root.reminderScript, "cancel", reminderRow.modelData.unit])
            }
          }
        }
      }

      PanelSeparator {}

      Column {
        width: parent.width
        spacing: Style.spacing.sm

        Item {
          width: parent.width
          height: pomoHeader.implicitHeight
          PanelSectionHeader { id: pomoHeader; text: "Pomodoro" }
          // one dot per focus block; a long break follows the last
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs
            visible: root.pomo.running
            Repeater {
              model: root.pomo.longEvery || 4
              Rectangle {
                required property int index
                readonly property int done: root.pomo.cycle > 0
                  ? (root.pomo.cycle - 1) % (root.pomo.longEvery || 4) + (root.pomo.phase === "work" ? 0 : 1) : 0
                width: Style.space(8)
                height: width
                radius: Style.shape.data
                color: index < done ? Color.accent : "transparent"
                border.width: Math.max(1, Style.space(1))
                border.color: index < done || (index === done && root.pomo.phase === "work") ? Color.accent : Color.menu.text
                opacity: index < done || (index === done && root.pomo.phase === "work") ? 1 : Style.emphasis.faint
              }
            }
          }
        }

        Item {
          width: parent.width
          height: Math.max(pomoTime.implicitHeight + pomoPhase.implicitHeight, pomoButtons.implicitHeight)
          visible: root.pomo.running

          Text {
            id: pomoTime
            anchors.left: parent.left
            anchors.top: parent.top
            textFormat: Text.PlainText
            text: root.pomo.remaining || "0:00"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.display
            font.bold: true
            // ticks every second: outline, never a MultiEffect
            style: Style.fx.glow > 0 ? Text.Outline : Text.Normal
            styleColor: Util.alpha(Color.accent, 0.35)
          }
          Text {
            id: pomoPhase
            anchors.left: parent.left
            anchors.top: pomoTime.bottom
            textFormat: Text.PlainText
            text: root.phaseLabel() + (root.pomo.cycle > 0 ? " :: pomodoro " + root.pomo.cycle : "")
            color: root.pomo.paused ? Color.menu.text : Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Row {
            id: pomoButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs
            PanelActionButton {
              iconText: root.pomo.paused ? "\u{f040a}" : "\u{f03e4}" // md-play / md-pause
              tooltipText: root.pomo.paused ? "Resume" : "Pause"
              foreground: Color.menu.text
              fontSize: Style.font.heading
              onClicked: root.run([root.pomodoroScript, "toggle"])
            }
            PanelActionButton {
              iconText: "\u{f04ad}" // md-skip_next
              tooltipText: "Skip to next phase"
              foreground: Color.menu.text
              fontSize: Style.font.heading
              onClicked: root.run([root.pomodoroScript, "skip"])
            }
            PanelActionButton {
              iconText: "\u{f04db}" // md-stop
              tooltipText: "Stop"
              foreground: Color.menu.text
              fontSize: Style.font.heading
              onClicked: root.run([root.pomodoroScript, "stop"])
            }
          }
        }

        BarGauge {
          width: parent.width
          height: Math.max(4, Style.space(4))
          visible: root.pomo.running
          segments: 32
          value: root.pomo.totalSeconds > 0
            ? Math.max(0, Math.min(1, 1 - root.pomo.remainingSeconds / root.pomo.totalSeconds)) : 0
          color: root.pomo.paused ? Color.menu.text : Color.accent
        }

        PanelRow {
          width: parent.width
          visible: !root.pomo.running
          glyph: "\u{f040a}" // md-play
          label: "Start a " + (root.pomo.defaultWork || 25) + " min focus block"
          filled: true
          onActivated: root.run([root.pomodoroScript, "start"])
        }
      }
    }
  }
}
