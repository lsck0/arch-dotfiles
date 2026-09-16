import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "ReminderFlowModel.js" as ReminderFlowModel

// Centered reminders + pomodoro overlay, styled like the app launcher. Typing
// sets a reminder (minutes, Enter, message, Enter); everything else is clickable.
// State lives in scripts/reminder.sh and scripts/pomodoro.sh, polled while open.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string step: "minutes"
  property string minutes: ""
  property string filterText: ""

  property var pomo: ({ running: false, paused: false, phase: "idle", remaining: "", remainingSeconds: 0, totalSeconds: 0, cycle: 0, longEvery: 4, defaultWork: 25 })
  property var reminders: []

  readonly property int cardWidth: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)
  readonly property string reminderScript: Paths.bin("reminder")
  readonly property string pomodoroScript: Paths.bin("pomodoro")
  readonly property string notifyScript: Paths.dotfiles + "/scripts/notification-send.sh"

  readonly property string promptText: step === "message"
    ? "Message for the " + minutes + " min reminder…"
    : "Remind me in … minutes"

  function open(payloadJson) {
    root.opened = true
    root.step = "minutes"
    root.minutes = ""
    root.filterText = ""
    root.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "panel.reminders")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function refresh() {
    if (!pomoProc.running) pomoProc.running = true
    if (!remindersProc.running) remindersProc.running = true
  }

  function run(argv) {
    Quickshell.execDetached(argv)
    refreshDelay.restart()
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

  Timer { id: refreshDelay; interval: 250; onTriggered: root.refresh() }
  Timer { interval: 1000; repeat: true; running: root.opened; onTriggered: root.refresh() }

  Process {
    id: pomoProc
    command: [root.pomodoroScript, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.pomo = JSON.parse(text || "{}") } catch (e) {} }
    }
  }

  Process {
    id: remindersProc
    command: [root.reminderScript, "show", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.reminders = JSON.parse(text || "{}").reminders || [] } catch (e) { root.reminders = [] }
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell-reminders"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: content.implicitHeight + card.contentTopInset + card.contentBottomInset + Style.spacing.md
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: Color.menu.background
      borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.filterText = ""
            else if (root.step === "message") root.step = "minutes"
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            root.filterText = root.filterText.slice(0, -1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submit()
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            // The minutes step only takes digits; the message step takes anything.
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
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.spacing.lg

        // ---- new reminder input, same headline field as the app launcher ----
        Item {
          width: parent.width
          height: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)

          Text {
            id: inputGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.step === "message" ? "\u{f009f}" : "\u{f0a92}"   // md-bell_ring_outline / md-bell_plus_outline
            color: Color.accent
            font.family: Style.font.iconFamily
            font.pixelSize: Style.font.heading
          }
          Text {
            anchors.left: inputGlyph.right
            anchors.leftMargin: Style.spacing.lg
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.filterText || root.promptText
            color: Color.menu.text
            opacity: root.filterText ? 1 : 0.58
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.step === "message"
            ? "Enter to set · empty for no message · Esc to go back"
            : "Type minutes and press Enter · Esc to close"
          color: Color.menu.text
          opacity: Style.emphasis.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        // Quick reminders, spread across the full width.
        Row {
          id: chips
          width: parent.width
          spacing: Style.spacing.sm
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

        // ---- reminders ----
        Column {
          width: parent.width
          spacing: Style.spacing.xs

          PanelSectionHeader { text: "Reminders" }

          Text {
            visible: root.reminders.length === 0
            textFormat: Text.PlainText
            text: "Nothing scheduled"
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
                anchors.leftMargin: -Style.spacing.sm
                anchors.rightMargin: -Style.spacing.sm
                radius: Style.cornerRadius
                color: rowHover.hovered ? Style.hoverFill : "transparent"
              }
              HoverHandler { id: rowHover }

              Text {
                id: bell
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "\u{f009c}"   // md-bell_outline
                color: Color.accent
                font.family: Style.font.iconFamily
                font.pixelSize: Style.font.icon
              }
              Text {
                anchors.left: bell.right
                anchors.leftMargin: Style.spacing.md
                anchors.right: when.left
                anchors.rightMargin: Style.spacing.md
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
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.sm
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
                iconText: "\u{f0156}"   // md-close
                tooltipText: "Cancel reminder"
                foreground: Color.menu.text
                onClicked: root.run([root.reminderScript, "cancel", reminderRow.modelData.unit])
              }
            }
          }
        }

        PanelSeparator {}

        // ---- pomodoro ----
        Column {
          width: parent.width
          spacing: Style.spacing.md

          Item {
            width: parent.width
            height: pomoHeader.implicitHeight
            PanelSectionHeader { id: pomoHeader; text: "Pomodoro" }
            // One dot per focus block in the current set; a long break follows the last.
            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm
              visible: root.pomo.running
              Repeater {
                model: root.pomo.longEvery || 4
                Rectangle {
                  required property int index
                  readonly property int done: root.pomo.cycle > 0
                    ? (root.pomo.cycle - 1) % (root.pomo.longEvery || 4) + (root.pomo.phase === "work" ? 0 : 1) : 0
                  width: Style.space(8)
                  height: width
                  radius: width / 2
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
            }
            Text {
              id: pomoPhase
              anchors.left: parent.left
              anchors.top: pomoTime.bottom
              textFormat: Text.PlainText
              text: root.phaseLabel() + (root.pomo.cycle > 0 ? "  ·  pomodoro " + root.pomo.cycle : "")
              color: root.pomo.paused ? Color.menu.text : Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Row {
              id: pomoButtons
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm
              PanelActionButton {
                iconText: root.pomo.paused ? "\u{f040a}" : "\u{f03e4}"   // md-play / md-pause
                tooltipText: root.pomo.paused ? "Resume" : "Pause"
                foreground: Color.menu.text
                fontSize: Style.font.heading
                onClicked: root.run([root.pomodoroScript, "toggle"])
              }
              PanelActionButton {
                iconText: "\u{f04ad}"   // md-skip_next
                tooltipText: "Skip to next phase"
                foreground: Color.menu.text
                fontSize: Style.font.heading
                onClicked: root.run([root.pomodoroScript, "skip"])
              }
              PanelActionButton {
                iconText: "\u{f04db}"   // md-stop
                tooltipText: "Stop"
                foreground: Color.menu.text
                fontSize: Style.font.heading
                onClicked: root.run([root.pomodoroScript, "stop"])
              }
            }
          }

          // Phase progress.
          Rectangle {
            width: parent.width
            height: Math.max(4, Style.space(4))
            radius: height / 2
            visible: root.pomo.running
            color: Style.selectedFillFor(Color.menu.text, Color.accent)
            Rectangle {
              height: parent.height
              radius: parent.radius
              color: root.pomo.paused ? Color.menu.text : Color.accent
              width: root.pomo.totalSeconds > 0
                ? parent.width * Math.max(0, Math.min(1, 1 - root.pomo.remainingSeconds / root.pomo.totalSeconds)) : 0
              Behavior on width { NumberAnimation { duration: 900 } }
            }
          }

          PanelRow {
            width: parent.width
            visible: !root.pomo.running
            glyph: "\u{f040a}"   // md-play
            label: "Start a " + (root.pomo.defaultWork || 25) + " min focus block"
            filled: true
            onActivated: root.run([root.pomodoroScript, "start"])
          }
        }
      }
    }
  }
}
