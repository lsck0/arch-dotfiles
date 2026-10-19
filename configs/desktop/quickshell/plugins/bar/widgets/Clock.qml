pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "clock"

  property date now: new Date()
  property date nowPrecise: new Date()
  property var zoneOffsets: []
  property real travelHours: 0

  readonly property var pomo: TimerState.pomo
  readonly property var reminders: TimerState.reminders

  implicitWidth: label.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  Rectangle {
    anchors.fill: parent
    radius: Style.shape.data
    color: mouseArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
  }

  readonly property real travelMs: travelHours * 3600000
  readonly property date travelledNow: new Date(now.getTime() + travelMs)
  readonly property date travelledPrecise: new Date(nowPrecise.getTime() + travelMs)

  // Qt.DayOfWeek counts Sunday as 7, Date.getDay() as 0
  readonly property int firstWeekday: Qt.locale().firstDayOfWeek % 7
  // Locale.dayName() names days in the formats locale; Qt.formatDate() in the language, like every other date here.
  // 2000-01-02 was a Sunday.
  readonly property var weekdayLetters: [0, 1, 2, 3, 4, 5, 6].map(i => Qt.formatDate(new Date(2000, 0, 2 + (firstWeekday + i) % 7), "ddd").charAt(0))
  readonly property string preciseFormat: Qt.locale().timeFormat(Locale.LongFormat).replace("ss", "ss.zzz").replace(/t+/, "t")

  readonly property string calendarKey: Qt.formatDate(travelledNow, "yyyy-MM-dd") + Qt.formatDate(now, "yyyy-MM-dd")
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
    var leading = (firstOfMonth.getDay() - root.firstWeekday + 7) % 7
    var today = root.now

    var cells = []
    for (let i = 0; i < leading; i++) cells.push(null)
    for (let day = 1; day <= daysInMonth; day++) {
      cells.push({
        day: day,
        isTravelled: travelled.getDate() === day,
        isToday: today.getFullYear() === year && today.getMonth() === month && today.getDate() === day,
      })
    }
    while (cells.length % 7 !== 0) cells.push(null)

    var weeks = []
    for (let w = 0; w < cells.length; w += 7) weeks.push(cells.slice(w, w + 7))
    return weeks
  }

  function monthLabel() {
    return Qt.formatDateTime(root.travelledNow, "MMMM yyyy")
  }

  function refreshOffsets() {
    if (!offsetsProc.running) offsetsProc.running = true
  }

  // on 2000-01-01, a day no zone switches dst, so qt's local-time formatting cannot move the wall clock an hour
  function timeInZone(spans) {
    var travelled = root.travelledNow
    var list = spans || []
    if (list.length === 0) return "--"
    var offsetSec = list[0].offsetSec
    for (let i = 1; i < list.length; i++)
      if (list[i].fromMs <= travelled.getTime()) offsetSec = list[i].offsetSec
    var wall = new Date(travelled.getTime() + offsetSec * 1000)
    return Qt.formatTime(new Date(2000, 0, 1, wall.getUTCHours(), wall.getUTCMinutes()), Util.timeFormat)
  }

  function dayLabel() {
    if (root.travelHours === 0) return ""
    var sign = root.travelHours > 0 ? "+" : "-"
    var hours = Math.abs(root.travelHours)
    var text = hours === Math.floor(hours) ? String(hours) : hours.toFixed(1)
    return " (" + sign + text + "h)"
  }

  Process {
    id: offsetsProc
    command: [Paths.barWidget("timezone-offsets.nu")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.zoneOffsets = JSON.parse(text || "[]") } catch (e) {}
      }
    }
  }

  Timer {
    interval: 60000 - (Date.now() % 60000) + 50
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: { root.now = new Date(); interval = 60000 - (Date.now() % 60000) + 50 }
  }

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
    text: Qt.formatDateTime(root.now, "ddd " + Util.dayFormat + " " + Util.timeFormat)
    color: root.bar ? root.bar.barForeground : Colors.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    font.letterSpacing: Style.displayTracking
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
    onOpened: { root.refreshOffsets(); TimerState.reload() }
    implicitWidth: Style.panelWidth.normal
    implicitHeight: content.implicitHeight + padding * 2 + titleInset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.sm

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: Qt.formatDateTime(root.travelledPrecise, root.preciseFormat)
        color: Colors.accent
        font.family: Style.font.family
        font.bold: true
        font.pixelSize: Style.font.display
        font.letterSpacing: Style.displayTracking
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: Qt.formatDate(root.travelledNow, Qt.locale().dateFormat(Locale.LongFormat))
        color: Colors.menu.text
        opacity: Style.emphasis.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: Style.labelTracking
      }

      PanelSectionHeader { text: "CALENDAR" }

      Item {
        width: parent.width
        implicitHeight: calGrid.implicitHeight + Style.spacing.xs * 2
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
            color: Colors.accent
            opacity: Style.emphasis.dim
            font.pixelSize: Style.font.caption
            font.family: Style.font.family
            font.letterSpacing: Style.headerTracking
          }

          Row {
            width: parent.width
            Repeater {
              model: root.weekdayLetters
              Text {
                required property string modelData
                width: content.width / 7
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: Colors.menu.text
                opacity: Style.emphasis.faint
                font.pixelSize: Style.font.caption
                font.family: Style.font.family
              }
            }
          }

          Repeater {
            model: root.calendarModel
            Row {
              id: week
              required property var modelData
              width: content.width
              Repeater {
                model: week.modelData
                Rectangle {
                  id: dayCell
                  required property var modelData
                  width: content.width / 7
                  height: Style.space(24)
                  radius: Style.shape.data
                  color: modelData && modelData.isTravelled ? Style.selectedFillFor(Colors.menu.text, Colors.accent) : "transparent"
                  border.width: modelData && modelData.isToday && !modelData.isTravelled ? Style.normalBorderWidth : 0
                  border.color: Util.alpha(Colors.accent, Style.hoverBorderAlpha)
                  Text {
                    anchors.centerIn: parent
                    text: dayCell.modelData ? dayCell.modelData.day : ""
                    color: dayCell.modelData && (dayCell.modelData.isTravelled || dayCell.modelData.isToday) ? Colors.accent : Colors.menu.text
                    font.bold: dayCell.modelData && dayCell.modelData.isTravelled
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
        model: root.zoneOffsets
        Item {
          id: zone
          required property var modelData
          width: content.width
          implicitHeight: zoneTime.implicitHeight
          height: implicitHeight
          Text {
            id: zoneMark
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: ">"
            color: Colors.accent
            opacity: Style.emphasis.dim
            font.pixelSize: Style.font.body
            font.family: Style.font.family
          }
          Text {
            anchors.left: zoneMark.right
            anchors.leftMargin: Style.spacing.xs
            anchors.right: zoneTime.left
            anchors.rightMargin: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter
            text: zone.modelData.zone
            color: Colors.menu.text
            font.pixelSize: Style.font.body
            font.family: Style.font.family
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Style.labelTracking
            elide: Text.ElideRight
          }
          Text {
            id: zoneTime
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.32
            horizontalAlignment: Text.AlignRight
            text: root.timeInZone(zone.modelData.spans)
            color: Colors.accent
            font.pixelSize: Style.font.body
            font.family: Style.font.family
            font.letterSpacing: Style.displayTracking
          }
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "TIMETRAVEL" + root.dayLabel() }

      Slider {
        width: parent.width
        value: root.travelHours
        minimum: -24
        maximum: 24
        step: 0.5
        fillColor: Colors.accent
        onMoved: function(v) { root.travelHours = v }
      }

      ActionButton {
        visible: root.travelHours !== 0
        width: parent.width
        label: "reset to now"
        tint: Colors.accent
        onActivated: root.travelHours = 0
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
          return parts.join(" :: ")
        }
        onActivated: {
          if (root.bar) root.bar.closePanel(root.moduleName)
          Quickshell.execDetached(Paths.ipcCall("shell", "summon", "panel.reminders", "{}"))
        }
      }
    }
  }
}
