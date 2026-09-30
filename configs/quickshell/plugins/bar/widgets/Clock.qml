import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "clock"

  property date now: new Date()
  // panel header only, everything else uses the 1s tick
  property date nowPrecise: new Date()
  property var zoneOffsets: []
  readonly property var sortedZoneOffsets: (root.zoneOffsets || []).slice().sort(function (a, b) { return a.offsetSec - b.offsetSec })
  // timetravel offset in hours
  property real travelHours: 0

  readonly property string pomodoroScript: Paths.script("pomodoro.sh")
  readonly property string reminderScript: Paths.script("reminder.sh")

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

  readonly property date travelledNow: new Date(now.getTime() + travelHours * 3600000)

  // rebuild the grid only when the travelled day changes
  readonly property string calendarKey: Qt.formatDate(travelledNow, "yyyy-MM-dd")
  property var calendarModel: []
  onCalendarKeyChanged: calendarModel = calendarWeeks()
  Component.onCompleted: {
    calendarModel = calendarWeeks()
    refreshOffsets()
  }

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

  // Qt formats in local time, so shift by local minus zone offset
  function timeInZone(offsetSec) {
    var travelled = root.travelledNow
    var shiftMs = (travelled.getTimezoneOffset() * 60 + offsetSec) * 1000
    return Qt.formatTime(new Date(travelled.getTime() + shiftMs), "HH:mm")
  }

  // half-hour steps need one decimal
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

  // 30ms is enough to look live
  Timer {
    interval: 30
    running: root.bar !== null && root.bar.activePanel === root.moduleName
    repeat: true
    onTriggered: root.nowPrecise = new Date()
  }

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: Qt.formatDateTime(root.now, "ddd dd.MM. HH:mm")
    color: root.bar ? root.bar.barForeground : Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    font.letterSpacing: Style.displayTracking
    layer.enabled: Style.fx.glow > 0
    layer.effect: Glow {}
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
    title: "CLOCK"
    onOpened: root.refreshOffsets()
    implicitWidth: Style.panelWidth.normal
    implicitHeight: content.implicitHeight + padding * 2 + titleInset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.lg

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: Qt.formatDateTime(root.nowPrecise, "HH:mm:ss.zzz") + " " + Qt.formatDateTime(root.nowPrecise, "t")
        color: Color.accent
        font.family: Style.font.family
        font.bold: true
        font.pixelSize: Style.font.display
        font.letterSpacing: Style.displayTracking
        layer.enabled: Style.fx.glow > 0
        layer.effect: Glow {}
      }

      PanelSectionHeader { text: "CALENDAR" + root.dayLabel() }

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
                  Text {
                    anchors.centerIn: parent
                    text: modelData ? modelData.day : ""
                    color: modelData && modelData.isToday ? Color.accent : Color.menu.text
                    font.bold: modelData && modelData.isToday
                    font.pixelSize: Style.font.caption
                    font.family: Style.font.family
                  }
                }
              }
            }
          }
        }
        HudFrame {}
      }

      PanelSeparator {}
      PanelSectionHeader { text: "TIMEZONES" }

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
            layer.effect: Glow {}
          }
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "TIMETRAVEL" }

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
