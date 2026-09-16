import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell. Zone offsets come from `date`/TZ
// (refreshed periodically for DST) rather than a JS timezone library —
// QtQml's Date has no real IANA timezone support beyond local/UTC.
BarWidget {
  id: root
  moduleName: "clock"

  property date now: new Date()
  // Millisecond-precision clock for the panel header only — the bar label
  // and every other consumer (calendar "today", zone offsets, timetravel)
  // only need whole-second resolution, so they keep the cheap 1s timer
  // below. This one only runs while the panel is actually open.
  property date nowPrecise: new Date()
  property var zoneOffsets: []
  // Timetravel: hours offset applied to every zone's preview simultaneously,
  // for "what time is it everywhere if we meet 3 hours from now".
  property real travelHours: 0

  // Pomodoro and reminders live in the shell-owned helpers under
  // configs/quickshell/scripts/ (linked into ~/.local/bin), backed by systemd
  // --user timers, so the notification
  // still fires with the shell restarted or dead. This panel is a readout and
  // a set of buttons; it holds no timer state of its own.
  readonly property string pomodoroScript: Paths.bin("pomodoro")
  readonly property string reminderScript: Paths.bin("reminder")

  property var pomo: ({ running: false, paused: false, phase: "idle", label: "Pomodoro", remaining: "", cycle: 0 })
  property var reminders: []

  function pomoRun(action) {
    Quickshell.execDetached([root.pomodoroScript, action])
    // The script writes state synchronously, but execDetached returns
    // immediately — give it a beat before reading back or the panel shows
    // the pre-click state.
    pomoDelay.restart()
  }

  function remindIn(minutes) {
    Quickshell.execDetached([root.reminderScript, String(minutes)])
    pomoDelay.restart()
  }

  function refreshPanelData() {
    if (!pomoProc.running) pomoProc.running = true
    if (!remindersProc.running) remindersProc.running = true
  }

  Timer { id: pomoDelay; interval: 250; onTriggered: root.refreshPanelData() }

  implicitWidth: label.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: mouseArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  // The date the calendar and the zone list are pointed at: now, shifted by
  // the timetravel slider. Scrubbing the slider therefore also scrubs the
  // month view — Sunday-first weeks, with *real* today (not the travelled
  // date) highlighted when it falls in the visible month.
  readonly property date travelledNow: new Date(now.getTime() + travelHours * 3600000)

  // The calendar grid is expensive to rebuild — 42 delegates — and it only
  // changes when the travelled *day* does. Bound directly to calendarWeeks(),
  // the Repeater's model depended on `now` and so rebuilt the whole grid once
  // a second for as long as the panel stayed open. Rebuild on this key
  // instead: once per day, or whenever the slider moves the date.
  readonly property string calendarKey: Qt.formatDate(travelledNow, "yyyy-MM-dd")
  property var calendarModel: []
  onCalendarKeyChanged: calendarModel = calendarWeeks()
  Component.onCompleted: calendarModel = calendarWeeks()

  function calendarWeeks() {
    var travelled = root.travelledNow
    var year = travelled.getFullYear()
    var month = travelled.getMonth()
    var firstOfMonth = new Date(year, month, 1)
    var daysInMonth = new Date(year, month + 1, 0).getDate()
    var startWeekday = firstOfMonth.getDay()
    var today = new Date()

    var cells = []
    for (var i = 0; i < startWeekday; i++) cells.push(null)
    for (var day = 1; day <= daysInMonth; day++) {
      cells.push({
        day: day,
        isToday: today.getFullYear() === year && today.getMonth() === month && today.getDate() === day,
      })
    }
    while (cells.length % 7 !== 0) cells.push(null)

    var weeks = []
    for (var w = 0; w < cells.length; w += 7) weeks.push(cells.slice(w, w + 7))
    return weeks
  }

  function monthLabel() {
    return Qt.formatDateTime(root.travelledNow, "MMMM yyyy")
  }

  function refreshOffsets() {
    if (!offsetsProc.running) offsetsProc.running = true
  }

  function timeInZone(offsetSec) {
    return Qt.formatTime(new Date(root.travelledNow.getTime() + offsetSec * 1000), "HH:mm")
  }

  // The slider steps in half hours, so toFixed(0) rendered +1.5h and +2h
  // identically as "+2h" — the header claimed a different offset from the one
  // the zone list below it was actually showing. One decimal, dropped when the
  // offset is whole, so the common case still reads "+3h".
  function dayLabel() {
    if (root.travelHours === 0) return ""
    var sign = root.travelHours > 0 ? "+" : "−"
    var hours = Math.abs(root.travelHours)
    var text = hours === Math.floor(hours) ? String(hours) : hours.toFixed(1)
    return " (" + sign + text + "h)"
  }

  Process {
    id: offsetsProc
    command: [Paths.barWidget("timezone-offsets.sh")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.zoneOffsets = JSON.parse(text || "[]") } catch (e) {}
      }
    }
  }

  Process {
    id: pomoProc
    command: [root.pomodoroScript, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.pomo = JSON.parse(text || "{}") } catch (e) {}
      }
    }
  }

  Process {
    id: remindersProc
    command: [root.reminderScript, "show", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text || "{}")
          root.reminders = d.reminders || []
        } catch (e) { root.reminders = [] }
      }
    }
  }

  // Only while the panel is actually open. The bar's Pomodoro indicator
  // keeps its own slower 10s poll for the collapsed case, so nothing runs
  // at 1s just because the shell is up.
  Timer {
    interval: 1000
    running: root.bar !== null && root.bar.activePanel === root.moduleName
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshPanelData()
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.now = new Date()
  }

  // 30ms (~33fps) rather than a true 1ms tick: the header only needs to
  // look continuously live to the eye, and this panel is the only consumer
  // of nowPrecise, so it only runs while open.
  Timer {
    interval: 30
    running: root.bar !== null && root.bar.activePanel === root.moduleName
    repeat: true
    onTriggered: root.nowPrecise = new Date()
  }

  Timer {
    interval: 15 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshOffsets()
  }

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: Qt.formatDateTime(root.now, "ddd dd.MM. HH:mm") + " " + Qt.formatDateTime(root.now, "t")
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
    // Opens centred under the clock itself. This used to anchor top-right
    // like every other panel, leaving a ~950px trip from a mid-bar trigger
    // to its own panel. Two earlier attempts failed: mapToGlobal (Wayland
    // gives clients no true global coordinates, so it never could work) and
    // a mapToItem binding, which was correct arithmetic evaluated once
    // before RowLayout had laid anything out and then never recomputed.
    // The fix was to make the position reactive rather than to look for a
    // third coordinate source — see BarWidget.barX and Bar.layoutRevision.
    anchorWidget: root
    onOpened: root.refreshOffsets()
    // Widened from 320: the pomodoro row (icon + countdown + three buttons)
    // and the six quick-reminder chips both need the extra room.
    implicitWidth: Style.panelWidth.normal + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.lg

      // Full precision (H:M:S.mmm) at the top, distinct from the bar
      // label's minute resolution — this is the one place in the shell
      // that shows a genuinely live-ticking clock.
      //
      // Color.menu.text, not Color.accent: this is the panel's primary
      // reading (the same role as Weather's big current-temperature text),
      // and Weather's convention is that primary content is the theme
      // foreground while accent is reserved for structure/selection
      // (PanelSectionHeader, the calendar's "today" cell, the timezone
      // slider's reset pill). A bare accent-colored headline here made the
      // clock panel read as a different palette from every other panel.
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: Qt.formatDateTime(root.nowPrecise, "HH:mm:ss:zzz")
        color: Color.menu.text
        font.family: Style.font.family
        font.bold: true
        font.pixelSize: Style.font.heading
        font.letterSpacing: Style.displayTracking
      }

      PanelSectionHeader { text: "CALENDAR" + root.dayLabel() }

      Column {
        width: parent.width
        spacing: Style.spacing.xs

        Row {
          width: parent.width
          Repeater {
            model: ["S", "M", "T", "W", "T", "F", "S"]
            Text {
              required property string modelData
              width: content.width / 7
              horizontalAlignment: Text.AlignHCenter
              text: modelData
              color: Color.menu.text
              opacity: Style.emphasis.faint
              font.pixelSize: Style.font.caption
              font.family: Style.font.family
            }
          }
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: root.monthLabel().toUpperCase()
          color: Color.accent
          opacity: 0.8
          font.pixelSize: Style.font.caption
          font.family: Style.font.family
          font.letterSpacing: Style.headerTracking
        }

        Repeater {
          model: root.calendarModel
          Row {
            required property var modelData
            width: content.width
            Repeater {
              model: modelData
              Rectangle {
                required property var modelData
                width: content.width / 7
                height: Style.space(24)
                radius: Style.cornerRadius
                color: modelData && modelData.isToday ? Style.selectedFillFor(Color.menu.text, Color.accent) : "transparent"
                opacity: 1.0
                Text {
                  anchors.centerIn: parent
                  text: modelData ? modelData.day : ""
                  color: modelData && modelData.isToday ? Color.accent : Color.menu.text
                  opacity: 1.0
                  font.bold: modelData && modelData.isToday
                  font.pixelSize: Style.font.caption
                  font.family: Style.font.family
                }
              }
            }
          }
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "TIMEZONES" }

      Repeater {
        model: root.zoneOffsets
        Row {
          required property var modelData
          width: content.width
          Text {
            width: parent.width * 0.6
            text: modelData.zone
            color: Color.menu.text
            font.pixelSize: Style.font.body
            font.family: Style.font.family
            elide: Text.ElideRight
          }
          Text {
            width: parent.width * 0.4
            horizontalAlignment: Text.AlignRight
            text: root.timeInZone(modelData.offsetSec)
            color: Color.menu.text
            font.pixelSize: Style.font.body
            font.family: Style.font.family
          }
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "TIMETRAVEL" }

      // Drag/scroll to preview every zone (and the calendar) at an offset
      // from now, for planning across timezones. Range: -24h to +24h.
      PanelSlider {
        width: parent.width
        value: root.travelHours
        minimum: -24
        maximum: 24
        step: 0.5
        fillColor: Color.accent
        onMoved: function(v) { root.travelHours = v }
      }

      Rectangle {
        visible: root.travelHours !== 0
        width: parent.width
        height: Style.space(24)
        radius: Style.cornerRadius
        color: Style.selectedFillFor(Color.menu.text, Color.accent)
        Text {
          anchors.centerIn: parent
          text: "Reset to now"
          color: Color.accent
          font.pixelSize: Style.font.caption
          font.family: Style.font.family
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.travelHours = 0
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "REMINDERS" + (root.reminders.length > 0 ? " · " + root.reminders.length : "") }

      // Six fixed quick-set chips rather than a free-text field — the
      // interactive (`reminder.sh -i`) flow already covers custom minutes
      // and a message; this row is for the common cases in one click.
      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Repeater {
          model: [5, 10, 15, 30, 45, 60]
          PanelActionButton {
            required property int modelData
            iconText: String(modelData) + "m"
            fontFamily: Style.font.family
            fontSize: Style.font.caption
            implicitWidth: Style.space(46)
            bordered: true
            onClicked: root.remindIn(modelData)
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.xs
        visible: root.reminders.length > 0

        Repeater {
          model: root.reminders
          Row {
            required property var modelData
            width: content.width
            spacing: Style.spacing.sm
            Text {
              width: parent.width - Style.space(80)
              text: modelData.label || ""
              color: Color.menu.text
              font.pixelSize: Style.font.body
              font.family: Style.font.family
              elide: Text.ElideRight
            }
            Text {
              width: Style.space(50)
              horizontalAlignment: Text.AlignRight
              text: modelData.remaining || ""
              color: Color.menu.text
              opacity: Style.emphasis.dim
              font.pixelSize: Style.font.caption
              font.family: Style.font.family
            }
            Text {
              width: Style.space(20)
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              text: "✕"
              color: Color.menu.text
              opacity: deleteArea.containsMouse ? 1.0 : 0.4
              font.pixelSize: Style.font.caption
              font.family: Style.font.family
              MouseArea {
                id: deleteArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // Through reminder.sh's own `cancel`, not a bare `systemctl
                // stop <timer>` from here: the script is what knows a
                // reminder is a .timer AND a .service AND a .message file,
                // and stopping only the timer left the other two behind.
                onClicked: {
                  Quickshell.execDetached([root.reminderScript, "cancel", modelData.unit])
                  pomoDelay.restart()
                }
              }
            }
          }
        }
      }

      Text {
        width: parent.width
        visible: root.reminders.length === 0
        textFormat: Text.PlainText
        text: "No outstanding reminders"
        color: Color.menu.text
        opacity: Style.emphasis.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      PanelSeparator {}
      PanelSectionHeader {
        text: root.pomo.running
          ? "POMODORO · " + String(root.pomo.label).toUpperCase()
            + (root.pomo.paused ? " (PAUSED)" : "")
          : "POMODORO"
      }

      Row {
        width: parent.width
        spacing: Style.spacing.md

        Text {
          anchors.verticalCenter: parent.verticalCenter
          // md-timer_sand while focusing, md-coffee on a break.
          text: root.pomo.phase === "work" ? "\u{f051f}" : (root.pomo.running ? "\u{f0176}" : "\u{f051f}")
          color: root.pomo.running ? Color.accent : Color.menu.text
          opacity: root.pomo.running ? 1 : 0.4
          font.family: Style.font.iconFamily
          font.pixelSize: Style.font.heading
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(150)
          spacing: Style.spacing.xxs
          Text {
            text: root.pomo.running ? root.pomo.remaining : "Not running"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: root.pomo.running ? Style.font.title : Style.font.body
          }
          Text {
            visible: root.pomo.running
            text: root.pomo.phase === "work" ? "Focusing" : "On break"
            color: Color.menu.text
            opacity: Style.emphasis.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs

          PanelActionButton {
            iconText: !root.pomo.running ? "\u{f040a}" : (root.pomo.paused ? "\u{f040a}" : "\u{f03e4}")
            tooltipText: !root.pomo.running ? "Start" : (root.pomo.paused ? "Resume" : "Pause")
            bordered: true
            onClicked: root.pomoRun("toggle")
          }
          PanelActionButton {
            visible: root.pomo.running
            iconText: "\u{f04ad}"
            tooltipText: "Skip"
            bordered: true
            onClicked: root.pomoRun("skip")
          }
          PanelActionButton {
            visible: root.pomo.running
            iconText: "\u{f04db}"
            tooltipText: "Stop"
            bordered: true
            onClicked: root.pomoRun("stop")
          }
        }
      }
    }
  }
}
