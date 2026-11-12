pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "Quotes.js" as Quotes

Item {
  id: root
  property string mainScreenName: ""
  property var shellHost: null
  readonly property int taskMax: 12
  readonly property int reminderMax: 4
  readonly property int cardWidth: Style.space(520)
  readonly property var reminderRows: {
    var out = []
    var list = TimerState.reminders || []
    for (let i = 0; i < list.length && i < root.reminderMax; i++) out.push({
      "label": String(list[i].label || ""),
      "remaining": String(list[i].remaining || "")
    })
    return out
  }
  readonly property var tasks: Array.prototype.slice.call(TaskState.tasks, 0, root.taskMax)
  readonly property int eventMax: 8
  readonly property var allDayAll: CalendarState.events.filter(e => e.allDay)
  readonly property var meetingsAll: CalendarState.events.filter(e => !e.allDay)
  readonly property var allDay: root.allDayAll.slice(0, root.eventMax)
  readonly property var meetings: root.meetingsAll.slice(0, root.eventMax)
  readonly property bool nowShown: TaskState.activeTask !== null || reminderRows.length > 0
  readonly property bool agendaEmpty: !nowShown && tasks.length === 0 && allDay.length === 0 && meetings.length === 0
  // narrower than this, the quote wraps a word per line: the card is left out instead
  readonly property int quoteMinWidth: Style.space(240)
  property var quote: Quotes.forDate(new Date())

  // the quote changes at midnight; a minute's poll is fine for a daily one and, unlike a timer aimed at midnight,
  // holds across a suspend
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      const next = Quotes.forDate(new Date())
      if (next !== root.quote) root.quote = next
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      readonly property var bar: root.shellHost ? root.shellHost.barFor(modelData) : null
      readonly property bool panelOverWidgets: panelOver(widgetColumn)
      readonly property bool panelOverQuote: panelOver(quoteCard)
      // toasts stack down the same top-right corner but draw above (overlay layer): the widgets stay, as hiding them on
      // every notification was more disruptive than the overlap
      readonly property bool widgetsHidden: panelOverWidgets

      // the bar's open panel drops from the top, so it covers an item it overlaps sideways and reaches down to
      function panelOver(item) {
        var panel = bar ? bar.activePanelWindow : null
        if (!panel || !panel.visible) return false
        var rect = panel.screenRect
        return rect.x < item.x + item.width && rect.x + rect.width > item.x && rect.y + rect.height > item.y
      }

      screen: modelData
      visible: String(modelData.name) === root.mainScreenName
      color: "transparent"
      WlrLayershell.namespace: "quickshell-desktop-widgets"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
      exclusionMode: ExclusionMode.Ignore

      anchors {
        top: true
        right: true
        bottom: true
        left: true
      }

      ScreenMoveRemap {
        id: screenGuard
        window: panel
      }

      // no card: the quote is set on the wallpaper itself, bottom left, large and quiet. It sits on the wallpaper, not on
      // the theme, so it is always light text in a soft dark halo (a photo caption), which reads on a light theme and a
      // busy or bright wallpaper alike without a box around it
      Column {
        id: quoteCard
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: Style.spacing.lg * 3
        anchors.leftMargin: Style.spacing.lg * 3
        // never under the agenda column on a narrow screen
        width: Math.min(Style.space(640), panel.width - widgetColumn.width - Style.spacing.lg * 6)
        spacing: Style.spacing.sm
        visible: !screenGuard.remapping && width >= root.quoteMinWidth
        opacity: panel.panelOverQuote ? 0 : 1
        layer.enabled: true

        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: Colors.wallpaperShadow
          shadowOpacity: 1
          shadowBlur: 1
          shadowScale: 1.02
          shadowHorizontalOffset: 0
          shadowVerticalOffset: 1
        }

        Label {
          width: parent.width
          text: "\u201c" + root.quote.text + "\u201d"
          wrapMode: Text.WordWrap
          font.italic: true
          font.pixelSize: Style.font.title + 4
          lineHeight: 1.15
          color: Colors.wallpaperText
        }

        Label {
          text: "\u2014 " + root.quote.author
          color: Colors.wallpaperText
          opacity: Style.emphasis.strong
          font.letterSpacing: 1
          font.capitalization: Font.AllUppercase
          caption: true
        }

        Behavior on opacity {
          NumberAnimation {
            duration: Style.motion.base
          }
        }
      }

      Column {
        id: widgetColumn
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Style.bar.sizeHorizontal + Style.spacing.lg
        anchors.rightMargin: Style.spacing.lg
        spacing: Style.spacing.md
        visible: !screenGuard.remapping
        opacity: panel.widgetsHidden ? 0 : 1

        Behavior on opacity {
          NumberAnimation {
            duration: Style.motion.base
          }
        }

        Card {
          heading: "Pomodoro"
          visible: TimerState.pomoRunning

          Item {
            width: parent.width
            implicitHeight: Math.max(phaseText.implicitHeight, clockText.implicitHeight)

            Label {
              id: phaseText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: TimerState.pomoPhaseLabel + (TimerState.pomoPaused ? " (paused)" : "")
            }

            Label {
              id: clockText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: Util.clock(TimerState.pomoRemainingSeconds)
              color: TimerState.pomo.phase === "work" ? Colors.accentText : Colors.okText
              font.pixelSize: Style.font.title
              font.bold: true
            }
          }

          Rectangle {
            width: parent.width
            height: Style.spacing.xs
            radius: Style.shape.data
            color: Style.selectedFill

            Rectangle {
              height: parent.height
              radius: parent.radius
              width: parent.width * (TimerState.pomoTotalSeconds > 0 ? Math.max(0, Math.min(1, 1 - TimerState.pomoRemainingSeconds / TimerState.pomoTotalSeconds)) : 0)
              color: TimerState.pomo.phase === "work" ? Colors.accent : Colors.ok
            }
          }
        }

        Card {
          id: agendaCard
          heading: "Agenda"
          visible: !root.agendaEmpty
          censored: ObsProcess.live
          onHeadingClicked: TaskState.panelOpen = true

          // one section per kind, each capped on its own and naming what the cap hid
          SectionTitle {
            text: "Now"
            visible: root.nowShown
            first: true
          }

          Line {
            visible: TaskState.activeTask !== null
            marker: "\u25b6"
            markerColor: Colors.accentText
            label: TaskState.activeTask ? TaskState.activeTask.desc : ""
            trailing: TaskState.activeElapsedText()
            trailingColor: Colors.accentText
          }

          Repeater {
            model: root.reminderRows

            delegate: Line {
              required property var modelData

              label: modelData.label
              trailing: modelData.remaining
              trailingColor: Colors.accent2Text
            }
          }

          More { hidden: (TimerState.reminders ? TimerState.reminders.length : 0) - root.reminderMax }

          SectionTitle {
            text: "All day"
            visible: root.allDay.length > 0
            first: !root.nowShown
          }

          Repeater {
            model: root.allDay

            delegate: Line {
              required property var modelData

              label: modelData.summary
              // "all day" is the section's name; only another day's date is left to say
              trailing: modelData.when.replace(/ ?all day$/, "")
              trailingColor: Colors.accent2Text
            }
          }

          More { hidden: root.allDayAll.length - root.eventMax }

          SectionTitle {
            text: "Meetings"
            visible: root.meetings.length > 0
            first: !root.nowShown && root.allDay.length === 0
          }

          Repeater {
            model: root.meetings

            delegate: Line {
              required property var modelData

              label: modelData.summary
              trailing: modelData.when
              trailingColor: Colors.accentText
            }
          }

          More { hidden: root.meetingsAll.length - root.eventMax }

          SectionTitle {
            text: "To do"
            visible: root.tasks.length > 0
            first: !root.nowShown && root.allDay.length === 0 && root.meetings.length === 0
          }

          Repeater {
            model: root.tasks

            delegate: Line {
              required property var modelData

              // overdue first, then priority: H warns, M takes the accent, L and none stay dim
              marker: modelData.overdue ? "!" : "\u25a1"
              markerColor: modelData.overdue ? Colors.urgentText
                : modelData.priority === "H" ? Colors.warnText
                : modelData.priority === "M" ? Colors.accentText : Colors.textDim
              label: modelData.desc
              trailing: [modelData.scheduled, modelData.due].filter(t => t !== "").join("  ")
              trailingColor: modelData.overdue ? Colors.urgentText : Colors.textDim
            }
          }

          More { hidden: TaskState.tasks.length - root.taskMax }
        }

        Card {
          id: notesCard
          heading: "Notes"
          visible: NotesState.disk.trim().length > 0 || notesEdit.text.length > 0
          censored: ObsProcess.live

          Label {
            width: parent.width
            visible: NotesState.conflict
            text: "changed on disk: ctrl+s overwrites it, ctrl+r takes it"
            color: Colors.urgentText
            wrapMode: Text.Wrap
            caption: true
          }

          TextEdit {
            id: notesEdit
            width: parent.width
            textFormat: TextEdit.PlainText
            color: Colors.foreground
            opacity: (text.length > 0 || activeFocus) ? Style.emphasis.strong : Style.emphasis.faint
            wrapMode: TextEdit.Wrap
            readOnly: ObsProcess.live
            selectByMouse: true
            persistentSelection: true
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            Component.onCompleted: text = NotesState.text
            onTextChanged: if (activeFocus)
              NotesState.edit(text)
            onActiveFocusChanged: if (!activeFocus)
              NotesState.save()
            Keys.onEscapePressed: notesEdit.focus = false
            Keys.onPressed: function(event) {
              event.accepted = NotesState.conflictKey(event.key, event.modifiers)
            }
          }

          Connections {
            target: NotesState
            function onTextChanged() { NotesState.syncInto(notesEdit) }
          }
        }
      }

      mask: Region {
        item: notesCard.visible && !panel.widgetsHidden ? notesCard : null

        Region {
          item: agendaCard.visible && !panel.widgetsHidden ? agendaCard.headingItem : null
        }
      }
    }
  }

  component Card: Rectangle {
    id: card
    property string heading: ""
    // while streaming or recording: the body blurs past reading, the heading stays, so the card still shows it is there
    property bool censored: false
    default property alias body: bodyCol.data
    readonly property alias headingItem: headingText

    signal headingClicked()

    width: root.cardWidth
    implicitHeight: inner.implicitHeight + Style.spacing.lg * 2
    radius: Style.shape.surface
    color: Colors.panelFill
    border.width: Style.normalBorderWidth
    border.color: Util.alpha(Colors.accent, Style.surface.ruleAlpha)

    Column {
      id: inner
      x: Style.spacing.lg
      y: Style.spacing.lg
      width: parent.width - Style.spacing.lg * 2
      spacing: Style.spacing.sm

      PanelSectionHeader {
        id: headingText
        text: card.heading

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: card.headingClicked()
        }
      }

      Column {
        id: bodyCol
        width: parent.width
        spacing: Style.spacing.xs
        layer.enabled: card.censored

        layer.effect: MultiEffect {
          blurEnabled: true
          blur: 1
          blurMax: 64
        }
      }
    }
  }

  component SectionTitle: Label {
    property bool first: false

    width: parent ? parent.width : 0
    topPadding: first ? 0 : Style.spacing.sm
    caption: true
    dim: true
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1
  }

  component More: Label {
    property int hidden: 0

    visible: hidden > 0
    leftPadding: markerWidth.width + Style.spacing.sm
    text: "+" + hidden + " more"
    caption: true
    dim: true
  }

  // the marker column's width, so labels line up whatever glyph a row carries
  TextMetrics {
    id: markerWidth
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    text: "\u25b6"
  }

  component Line: Item {
    property string marker: ">"
    property color markerColor: Colors.textDim
    property string label: ""
    property string trailing: ""
    property color trailingColor: Colors.foreground

    width: parent ? parent.width : 0
    implicitHeight: Math.max(labelText.implicitHeight, trailingText.implicitHeight)

    Label {
      id: markerText
      anchors.left: parent.left
      anchors.baseline: labelText.baseline
      width: markerWidth.width
      horizontalAlignment: Text.AlignHCenter
      text: parent.marker
      color: parent.markerColor
    }

    // a long title wraps onto a second line instead of losing its end; the time stays on the first line
    Label {
      id: labelText
      anchors.left: markerText.right
      anchors.leftMargin: Style.spacing.sm
      anchors.right: trailingText.left
      anchors.rightMargin: Style.spacing.sm
      anchors.top: parent.top
      text: parent.label
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }

    Label {
      id: trailingText
      anchors.right: parent.right
      anchors.baseline: labelText.baseline
      text: parent.trailing
      color: parent.trailingColor
    }
  }
}
