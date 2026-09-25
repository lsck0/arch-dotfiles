import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell.
BarWidget {
  id: root
  moduleName: "clock"

  property date now: new Date()
  // Millisecond-precision clock for the panel header only — the bar label and every other consumer (calendar "today", zone offsets, timetravel) only need whole-second resolution, so they keep the cheap 1s timer below.
  property date nowPrecise: new Date()
  property var zoneOffsets: []
  // World clocks ordered west-to-east by UTC offset.
  readonly property var sortedZoneOffsets: (root.zoneOffsets || []).slice().sort(function (a, b) { return a.offsetSec - b.offsetSec })
  // Timetravel: hours offset applied to every zone's preview simultaneously, for "what time is it everywhere if we meet 3 hours from now".
  property real travelHours: 0

  // Pomodoro and reminders live in the shell-owned helpers under configs/quickshell/scripts/ (linked into ~/.local/bin), backed by systemd --user timers, so the notification still fires with the shell restarted or dead.
  readonly property string pomodoroScript: Paths.bin("pomodoro")
  readonly property string reminderScript: Paths.bin("reminder")

  property var pomo: ({ running: false, paused: false, phase: "idle", label: "Pomodoro", remaining: "", cycle: 0 })
  property var reminders: []

  function refreshPanelData() {
    if (!pomoProc.running) pomoProc.running = true
    if (!remindersProc.running) remindersProc.running = true
  }

  implicitWidth: label.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: mouseArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  // The date the calendar and the zone list are pointed at: now, shifted by the timetravel slider.
  readonly property date travelledNow: new Date(now.getTime() + travelHours * 3600000)

  // The calendar grid is expensive to rebuild — 42 delegates — and it only changes when the travelled *day* does.
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

  // The slider steps in half hours, so toFixed(0) rendered +1.5h and +2h identically as "+2h" — the header claimed a different offset from the one the zone list below it was actually showing.
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

  // Only while the panel is actually open.
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

  // 30ms (~33fps) rather than a true 1ms tick: the header only needs to look continuously live to the eye, and this panel is the only consumer of nowPrecise, so it only runs while open.
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
    text: Qt.formatDateTime(root.now, "ddd dd.MM. HH:mm")
    color: root.bar ? root.bar.barForeground : Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    // Tight tracking + subtle accent bloom for the big mono readout.
    font.letterSpacing: Style.displayTracking
    layer.enabled: Style.fx.glow > 0
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: Style.fx.glowColor
      shadowBlur: 1.0
      shadowVerticalOffset: 0
      shadowHorizontalOffset: 0
      blurMax: Style.fx.glowRadius
      autoPaddingEnabled: true
    }
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
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    // Opens centred under the clock itself.
    anchorWidget: root
    // Terminal-window title strip, rendered by the shared card.
    title: "CLOCK"
    onOpened: root.refreshOffsets()
    // Widened from 320: the pomodoro row (icon + countdown + three buttons) and the six quick-reminder chips both need the extra room.
    implicitWidth: Style.panelWidth.normal + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.lg

      // Top headroom so the overlaid title strip never covers the hero readout.
      Item { width: 1; height: Style.spacing.xl }

      // Full precision (H:M:S.mmm) at the top, distinct from the bar label's minute resolution — this is the one place in the shell that shows a genuinely live-ticking clock.
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: Qt.formatDateTime(root.nowPrecise, "HH:mm:ss.zzz") + " " + Qt.formatDateTime(root.nowPrecise, "t")
        // Glowing accent mono hero: the shell's one live-ticking readout.
        color: Color.accent
        font.family: Style.font.family
        font.bold: true
        font.pixelSize: Style.font.display
        font.letterSpacing: Style.displayTracking
        layer.enabled: Style.fx.glow > 0
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: Style.fx.glowColor
          shadowBlur: 1.0
          shadowVerticalOffset: 0
          shadowHorizontalOffset: 0
          blurMax: Style.fx.glowRadius
          autoPaddingEnabled: true
        }
      }

      PanelSectionHeader { text: "CALENDAR" + root.dayLabel() }

      // HUD-framed calendar grid: corner brackets over a tracked month header.
      Item {
        width: parent.width
        implicitHeight: calGrid.implicitHeight + Style.spacing.sm * 2
        height: implicitHeight

      Column {
        id: calGrid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs

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
        // HUD corner brackets framing the whole grid.
        HudFrame {}
      }

      PanelSeparator {}
      PanelSectionHeader { text: "TIMEZONES" }

      // World clocks as a mono terminal table: reticle marker, tracked zone, glowing flush-right time.
      Repeater {
        model: root.sortedZoneOffsets
        Item {
          required property var modelData
          width: content.width
          implicitHeight: zoneTime.implicitHeight
          height: implicitHeight
          Text {
            id: zoneMark
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: ">"
            color: Color.accent
            opacity: Style.emphasis.dim
            font.pixelSize: Style.font.body
            font.family: Style.font.family
          }
          Text {
            anchors.left: zoneMark.right
            anchors.leftMargin: Style.spacing.sm
            anchors.right: zoneTime.left
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.zone
            color: Color.menu.text
            font.pixelSize: Style.font.body
            font.family: Style.font.family
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Style.headerTracking * 0.4
            elide: Text.ElideRight
          }
          Text {
            id: zoneTime
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.32
            horizontalAlignment: Text.AlignRight
            text: root.timeInZone(modelData.offsetSec)
            color: Color.accent
            font.pixelSize: Style.font.body
            font.family: Style.font.family
            font.letterSpacing: Style.displayTracking
            layer.enabled: Style.fx.glow > 0
            layer.effect: MultiEffect {
              shadowEnabled: true
              shadowColor: Style.fx.glowColor
              shadowBlur: 1.0
              shadowVerticalOffset: 0
              shadowHorizontalOffset: 0
              blurMax: Style.fx.glowRadius
              autoPaddingEnabled: true
            }
          }
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "TIMETRAVEL" }

      // Drag/scroll to preview every zone (and the calendar) at an offset from now, for planning across timezones.
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
      PanelSectionHeader { text: "TIMERS" }

      // Reminders and the pomodoro live in the centered overlay (plugins/reminders).
      PanelRow {
        width: parent.width
        glyph: root.pomo.running ? (root.pomo.phase === "work" ? "\u{f051f}" : "\u{f0176}") : "\u{f009c}"
        label: "Reminders & pomodoro"
        trailing: {
          var parts = []
          if (root.pomo.running) parts.push((root.pomo.paused ? "Paused " : "") + root.pomo.remaining)
          if (root.reminders.length) parts.push(root.reminders.length + (root.reminders.length === 1 ? " reminder" : " reminders"))
          return parts.join(" · ")
        }
        onActivated: {
          if (root.bar) root.bar.closePanel(root.moduleName)
          Quickshell.execDetached(Paths.ipcCall("shell", "summon", "panel.reminders", "{}"))
        }
      }
    }
  }
}
