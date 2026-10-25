pragma ComponentBehavior: Bound
import Quickshell
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
  property var renameTarget: null

  readonly property var pomo: TimerState.pomo
  readonly property var reminders: TimerState.reminders

  readonly property string reminderScript: Paths.script("reminder.nu")
  readonly property string pomodoroScript: Paths.script("pomodoro.nu")

  readonly property string promptText: step === "name" ? "Name for the " + minutes + " min reminder (optional)"
    : step === "rename" ? "New name for " + (renameTarget ? renameTarget.label : "")
    : "Remind me in ... minutes, then a name"

  function reset() {
    root.step = "minutes"
    root.minutes = ""
    root.filterText = ""
    root.renameTarget = null
  }

  function open() {
    root.opened = true
    root.reset()
    root.pomoDraft = ({})
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

  function remindIn(minutes, name) {
    run([root.reminderScript].concat(ReminderFlowModel.reminderArgs(minutes, name)))
  }

  function askName(minutes) {
    root.minutes = String(minutes)
    root.step = "name"
    root.filterText = ""
    keyCatcher.forceActiveFocus()
  }

  function askRename(reminder) {
    root.renameTarget = reminder
    root.step = "rename"
    root.filterText = ""
    keyCatcher.forceActiveFocus()
  }

  function submit() {
    if (root.step === "minutes") {
      if (!root.filterText.trim()) return
      let entry = ReminderFlowModel.parseEntry(root.filterText)
      if (!entry) {
        Quickshell.execDetached(["notify-send", "-a", "quickshell-action", "-u", "low", "Invalid reminder", "Start with the number of minutes"])
        return
      }
      if (entry.name) {
        root.remindIn(entry.minutes, entry.name)
        root.reset()
      } else {
        root.askName(entry.minutes)
      }
      return
    }
    if (root.step === "rename") {
      if (root.renameTarget) run([root.reminderScript, "rename", root.renameTarget.unit, root.filterText.trim()])
      root.reset()
      return
    }
    root.remindIn(root.minutes, root.filterText)
    root.reset()
  }

  property var pomoDraft: ({})
  readonly property var pomoLengths: [
    { key: "focus", label: "Focus", step: 5, minimum: 1, maximum: 180, unit: "min" },
    { key: "break", label: "Break", step: 1, minimum: 1, maximum: 60, unit: "min" },
    { key: "long", label: "Long break", step: 5, minimum: 1, maximum: 120, unit: "min" },
    { key: "cycles", label: "Cycles", step: 1, minimum: 1, maximum: 12, unit: "" }
  ]

  function pomoValue(key) {
    return Number(key in root.pomoDraft ? root.pomoDraft[key] : TimerState.pomoConfig[key])
  }

  function pomoStep(length, direction) {
    var value = root.pomoValue(length.key)
    var next = direction > 0 ? (Math.floor(value / length.step) + 1) * length.step
                             : (Math.ceil(value / length.step) - 1) * length.step
    next = Math.max(length.minimum, Math.min(length.maximum, next))
    if (next === value) return
    root.pomoDraft = Util.mapSet(root.pomoDraft, length.key, next)
    pomoCommit.restart()
  }

  Timer {
    id: pomoCommit
    interval: 700
    onTriggered: TimerState.setPomoConfig(root.pomoDraft)
  }

  Connections {
    target: TimerState
    function onPomoConfigChanged() { if (!pomoCommit.running && !TimerState.pomoSaving) root.pomoDraft = ({}) }
  }

  function phaseLabel() {
    if (!pomo.running) return "Ready"
    if (pomo.paused) return "Paused"
    return pomo.phase === "work" ? "Focus" : pomo.phase === "long" ? "Long break" : "Break"
  }

  Binding { target: TimerState; property: "overlayOpen"; value: root.opened }

  OverlayCard {
    open: root.opened
    name: "reminders"
    title: "reminders"
    prompt: true
    query: root.filterText
    placeholder: root.promptText
    hints: root.step === "minutes"
      ? [["0-9", "minutes"], ["ENTER", "next"], ["ESC", "close"]]
      : [["ENTER", "set"], ["ESC", "back"]]
    cardWidth: Style.space(560)
    cardHeight: flowContent.implicitHeight + chromeHeight
    onDismissed: root.close()

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (root.filterText) root.filterText = ""
          else if (root.step !== "minutes") root.reset()
          else root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Backspace) {
          root.filterText = root.filterText.slice(0, -1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.submit()
          event.accepted = true
        } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
          if (root.step !== "minutes" || /[0-9]/.test(event.text) || /^[0-9]/.test(root.filterText)) root.filterText += event.text
          event.accepted = true
        }
      }
    }

    Column {
      id: flowContent
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
          Button {
            variant: "chip"
            required property int modelData
            width: (chips.width - chips.spacing * (chips.presets.length - 1)) / chips.presets.length
            text: modelData + " min"
            onClicked: root.askName(modelData)
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
          color: Colors.menu.text
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
              color: Colors.accent
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
              color: Colors.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
            Row {
              id: when
              anchors.right: rename.left
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs
              Text {
                textFormat: Text.PlainText
                text: "in " + (reminderRow.modelData.remaining || "")
                color: Colors.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              Text {
                textFormat: Text.PlainText
                text: reminderRow.modelData.atTime || ""
                color: Colors.menu.text
                opacity: Style.emphasis.faint
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }
            Button {
              variant: "icon"
              id: rename
              anchors.right: cancel.left
              anchors.verticalCenter: parent.verticalCenter
              iconText: "\u{f03eb}" // md-pencil
              tooltipText: "Rename reminder"
              foreground: Colors.menu.text
              onClicked: root.askRename(reminderRow.modelData)
            }
            Button {
              variant: "icon"
              id: cancel
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "\u{f0156}"
              tooltipText: "Cancel reminder"
              foreground: Colors.menu.text
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
                color: index < done ? Colors.accent : "transparent"
                border.width: Math.max(1, Style.space(1))
                border.color: index < done || (index === done && root.pomo.phase === "work") ? Colors.accent : Colors.menu.text
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
            color: Colors.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.display
            font.bold: true
            style: Style.fx.glow > 0 ? Text.Outline : Text.Normal
            styleColor: Util.alpha(Colors.accent, 0.35)
          }
          Text {
            id: pomoPhase
            anchors.left: parent.left
            anchors.top: pomoTime.bottom
            textFormat: Text.PlainText
            text: root.phaseLabel() + (root.pomo.cycle > 0 ? " :: pomodoro " + root.pomo.cycle : "")
            color: root.pomo.paused ? Colors.menu.text : Colors.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Row {
            id: pomoButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs
            Button {
              variant: "icon"
              iconText: root.pomo.paused ? "\u{f040a}" : "\u{f03e4}"
              tooltipText: root.pomo.paused ? "Resume" : "Pause"
              foreground: Colors.menu.text
              fontSize: Style.font.heading
              onClicked: root.run([root.pomodoroScript, "toggle"])
            }
            Button {
              variant: "icon"
              iconText: "\u{f04ad}"
              tooltipText: "Skip to next phase"
              foreground: Colors.menu.text
              fontSize: Style.font.heading
              onClicked: root.run([root.pomodoroScript, "skip"])
            }
            Button {
              variant: "icon"
              iconText: "\u{f04db}"
              tooltipText: "Stop"
              foreground: Colors.menu.text
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
          color: root.pomo.paused ? Colors.menu.text : Colors.accent
        }

        PanelRow {
          width: parent.width
          visible: !root.pomo.running
          glyph: "\u{f040a}"
          label: "Start a " + root.pomoValue("focus") + " min focus block"
          filled: true
          onActivated: root.run([root.pomodoroScript, "start"])
        }

        Row {
          id: lengths
          width: parent.width
          spacing: Style.spacing.xs

          Repeater {
            model: root.pomoLengths
            Column {
              id: length
              required property var modelData
              width: (lengths.width - lengths.spacing * (root.pomoLengths.length - 1)) / root.pomoLengths.length
              spacing: Style.spacing.xxs

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: length.modelData.label
                color: Colors.menu.text
                opacity: Style.emphasis.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Item {
                width: parent.width
                height: Math.max(less.height, amount.implicitHeight)

                Button {
                  variant: "icon"
                  id: less
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "\u{f0374}" // md-minus
                  tooltipText: "Shorter"
                  foreground: Colors.menu.text
                  enabled: root.pomoValue(length.modelData.key) > length.modelData.minimum
                  onClicked: root.pomoStep(length.modelData, -1)
                }
                Text {
                  id: amount
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: root.pomoValue(length.modelData.key) + (length.modelData.unit ? " " + length.modelData.unit : "")
                  color: Colors.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                Button {
                  variant: "icon"
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "\u{f0415}" // md-plus
                  tooltipText: "Longer"
                  foreground: Colors.menu.text
                  enabled: root.pomoValue(length.modelData.key) < length.modelData.maximum
                  onClicked: root.pomoStep(length.modelData, 1)
                }
              }
            }
          }
        }
      }
    }
  }
}
