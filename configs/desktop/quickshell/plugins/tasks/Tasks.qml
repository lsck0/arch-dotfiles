pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  property string view: "tasks"
  readonly property var views: ["tasks", "notes", "inbox"]
  property string inputMode: ""
  property string filterText: ""
  property int selectedIndex: 0
  property string selectedUuid: ""
  property var modifyTask: null

  readonly property bool opened: TaskState.panelOpen
  readonly property int rowHeight: Style.space(40)
  readonly property int reminderShownMax: 3

  component StripLine: Label {
    width: parent.width
    caption: true
  }

  readonly property var filtered: {
    var needle = root.filterText.trim().toLowerCase()
    return (TaskState.tasks || []).filter(function (t) {
      return !needle || (t.desc + " " + t.project + " " + t.tags.join(" ")).toLowerCase().indexOf(needle) >= 0
    })
  }

  readonly property var selectedTask: filtered.length > 0 && selectedIndex >= 0 && selectedIndex < filtered.length
    ? filtered[selectedIndex] : null

  readonly property var hints: view === "notes" && NotesState.conflict
    ? [["CTRL+S", "overwrite disk"], ["CTRL+R", "take disk"], ["TAB", "inbox"], ["ESC", "close"]]
    : view === "notes" ? [["TAB", "inbox"], ["ESC", "close"]]
    : view === "inbox" ? [["^/v", "scroll"], ["TAB", "tasks"], ["ESC", "close"]]
    : inputMode === "add" ? [["ENTER", "add"], ["TAB", "complete"], ["ESC", "back"]]
    : inputMode === "modify" ? [["ENTER", "modify"], ["TAB", "complete"], ["ESC", "back"]]
    : inputMode === "filter" ? [["ENTER", "keep"], ["TAB", "notes"], ["ESC", "clear"]]
    : [["^/v", "select"], ["ENTER/D", "done"], ["S", "start/stop"], ["X", "delete"], ["E", "edit"], ["U", "undo"],
       ["A", "add"], ["/", "filter"], ["TAB", "notes"], ["ESC", "close"]]

  function open() {
    TaskState.panelOpen = true
  }

  function close() {
    TaskState.panelOpen = false
  }

  function toggle() {
    TaskState.panelOpen = !TaskState.panelOpen
  }

  onOpenedChanged: {
    if (opened) {
      root.inputMode = ""
      root.filterText = ""
      root.selectedIndex = 0
      root.selectedUuid = ""
      TaskState.refresh()
      root.focusView()
    } else {
      NotesState.flush()
      keyCatcher.forceActiveFocus()
    }
  }

  function focusView() {
    Qt.callLater(function () {
      if (root.view === "notes") notesEdit.forceActiveFocus()
      else if (root.view === "inbox") inboxEdit.forceActiveFocus()
      else if (root.inputMode !== "") input.forceActiveFocus()
      else keyCatcher.forceActiveFocus()
    })
  }

  // TAB walks the views forward, SHIFT+TAB back
  function cycleView(key) {
    var step = key === Qt.Key_Backtab ? root.views.length - 1 : 1
    root.setView(root.views[(root.views.indexOf(root.view) + step) % root.views.length])
  }

  function setView(name) {
    if (root.view === "notes") NotesState.save()
    root.view = name
    if (name === "inbox") inboxFlick.contentY = Math.max(0, inboxFlick.contentHeight - inboxFlick.height)
    root.focusView()
  }

  onFilteredChanged: {
    if (root.selectedUuid) {
      for (let i = 0; i < filtered.length; i++) {
        if (filtered[i].uuid === root.selectedUuid) { root.selectedIndex = i; return }
      }
    }
    root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, filtered.length - 1))
    root.selectedUuid = root.selectedTask ? root.selectedTask.uuid : ""
  }

  function select(index) {
    if (filtered.length === 0) return
    root.selectedIndex = Math.max(0, Math.min(index, filtered.length - 1))
    root.selectedUuid = filtered[root.selectedIndex].uuid
    taskList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function startInput(mode) {
    root.modifyTask = mode === "modify" ? root.selectedTask : null
    root.inputMode = mode
    input.text = mode === "filter" ? root.filterText : mode === "modify" ? TaskState.commandText(root.modifyTask) : ""
    input.forceActiveFocus()
  }

  function endInput() {
    root.inputMode = ""
    keyCatcher.forceActiveFocus()
  }

  function listKey(key, text) {
    if (key === Qt.Key_Escape) {
      if (root.filterText) root.filterText = ""
      else root.close()
    } else if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
      root.cycleView(key)
    } else if (key === Qt.Key_Up || text === "k") {
      root.select(root.selectedIndex - 1)
    } else if (key === Qt.Key_Down || text === "j") {
      root.select(root.selectedIndex + 1)
    } else if (key === Qt.Key_PageUp) {
      root.select(root.selectedIndex - 6)
    } else if (key === Qt.Key_PageDown) {
      root.select(root.selectedIndex + 6)
    } else if (key === Qt.Key_Home || text === "g") {
      root.select(0)
    } else if (key === Qt.Key_End || text === "G") {
      root.select(root.filtered.length - 1)
    } else if (key === Qt.Key_Return || key === Qt.Key_Enter || text === "d") {
      TaskState.markDone(root.selectedTask)
    } else if (text === "s") {
      TaskState.toggleActive(root.selectedTask)
    } else if (key === Qt.Key_Delete || text === "x") {
      TaskState.remove(root.selectedTask)
    } else if (text === "e") {
      if (root.selectedTask) root.startInput("modify")
    } else if (text === "u") {
      TaskState.undoLast()
    } else if (text === "a" || text === "i") {
      root.startInput("add")
    } else if (text === "/") {
      root.startInput("filter")
    } else {
      return false
    }
    return true
  }

  function inputKey(key, modifiers) {
    if (Util.isWordDelete(key, modifiers)) {
      input.remove(Util.wordStart(input.text, input.cursorPosition), input.cursorPosition)
      if (root.inputMode === "filter") root.filterText = input.text
    } else if (key === Qt.Key_Escape) {
      if (root.inputMode === "filter") root.filterText = ""
      input.text = ""
      root.endInput()
    } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
      if (root.inputMode === "add") {
        TaskState.add(input.text)
        input.text = ""
      } else if (root.inputMode === "modify") {
        TaskState.modify(root.modifyTask, input.text)
        input.text = ""
        root.endInput()
      } else {
        root.endInput()
      }
    } else if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
      // in add and modify mode TAB only completes: a word with nothing to complete must not leave the line
      if (key === Qt.Key_Tab && (root.inputMode === "add" || root.inputMode === "modify")) root.completeInput()
      else root.cycleView(key)
    } else if (root.inputMode === "filter" && (key === Qt.Key_Down || key === Qt.Key_Up)) {
      root.endInput()
      root.select(key === Qt.Key_Down ? 0 : root.filtered.length - 1)
    } else {
      return false
    }
    return true
  }

  function known(field) {
    var seen = {}
    var list = TaskState.tasks || []
    for (let i = 0; i < list.length; i++) {
      let values = field === "tags" ? list[i].tags : [list[i].project]
      for (let j = 0; j < values.length; j++) if (values[j]) seen[values[j]] = true
    }
    return Object.keys(seen).sort()
  }

  readonly property var fieldKeywords: ["project:", "due:", "scheduled:", "wait:", "until:", "priority:", "recur:"]
  readonly property var dateKeywords: ["due:", "sch:", "scheduled:", "wait:", "until:"]
  readonly property var priorities: ["H", "M", "L"]
  // taskwarrior's named dates and recurrence periods; a relative value (3d, 2wk, 15:00) has nothing to complete
  readonly property var namedDates: ["now", "today", "tomorrow", "yesterday", "sod", "eod", "sow", "eow", "soww", "eoww",
    "som", "eom", "soq", "eoq", "soy", "eoy", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    "later", "someday"]
  readonly property var recurPeriods: ["daily", "weekdays", "weekly", "biweekly", "monthly", "bimonthly", "quarterly",
    "semiannual", "annual", "yearly"]

  // after a keyword's colon complete its value, else complete the bare word into the keyword
  function completeInput() {
    var head = input.text.slice(0, input.cursorPosition)
    var start = head.search(/\S*$/)
    var word = head.slice(start)
    var value = word.match(/^([+-]|pro(?:ject)?:|due:|sch(?:eduled)?:|wait:|until:|recur:|prio(?:rity)?:)(.*)$/)
    if (value) return root.completeValue(start, value[1], value[2])
    if (!word) return false
    var field = Util.completion(word, root.fieldKeywords)
    if (field === word) return false
    input.remove(start, input.cursorPosition)
    input.insert(start, field)
    return true
  }

  // dates complete against taskwarrior's named dates, recur: against its periods; a relative value matches none and
  // stays as typed
  function completeValue(start, keyword, partial) {
    var pool = keyword.length === 1 ? root.known("tags")
      : keyword === "priority:" || keyword === "prio:" ? root.priorities
      : root.dateKeywords.indexOf(keyword) >= 0 ? root.namedDates
      : keyword === "recur:" ? root.recurPeriods
      : root.known("project")
    var done = Util.completion(partial, pool)
    var unique = pool.filter(function (c) { return c.indexOf(done) === 0 }).length === 1
    input.remove(start, input.cursorPosition)
    input.insert(start, keyword + done + (unique ? " " : ""))
    return true
  }

  // a rejected add or modify comes back into the line, unless something new is typed there already
  Connections {
    target: TaskState
    function onInputFailed(op, uuid, text) {
      if (!root.opened || root.view !== "tasks" || (root.inputMode !== "" && input.text !== "")) return
      if (op === "modify") {
        let i = root.filtered.findIndex(function (t) { return t.uuid === uuid })
        if (i < 0) return
        root.select(i)
      }
      root.startInput(op)
      input.text = text
    }
  }

  readonly property string lastActionText: TaskState.lastAction
    ? TaskState.lastAction.op + " :: " + TaskState.lastAction.desc + " :: u to undo" : ""

  function metaText(task) {
    var parts = []
    if (task.project) parts.push(task.project)
    if (task.priority) parts.push("priority:" + task.priority)
    if (task.recur) parts.push("recur:" + task.recur)
    if (task.until) parts.push(task.until)
    if (task.blocked) parts.push("blocked")
    for (let i = 0; i < task.tags.length; i++) parts.push("+" + task.tags[i])
    var tracked = TaskState.trackedText(task.desc)
    if (tracked) parts.push(tracked + " today")
    return parts.join(" ")
  }

  IpcHandler {
    target: "tasks"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.open(null); return "ok" }
    function close(): string { root.close(); return "ok" }
    // capture.nu and task-sync.service call it after an add from outside the shell
    function refresh(): string { TaskState.refresh(); return "ok" }
  }

  OverlayCard {
    id: panel
    open: root.opened
    name: "tasks"
    title: root.view
    hints: root.hints
    cardWidth: Style.space(760)
    cardHeight: Style.space(540)
    onDismissed: root.close()

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function (event) { event.accepted = root.listKey(event.key, event.text) }
    }

    Item {
      anchors.fill: parent

      Row {
        id: viewTabs
        anchors.top: parent.top
        anchors.left: parent.left
        spacing: Style.spacing.lg

        Repeater {
          model: [
            { name: "tasks", label: "tasks :: " + TaskState.pendingCount + (TaskState.overdueCount > 0 ? " :: " + TaskState.overdueCount + " overdue" : "") },
            { name: "notes", label: "notes" + (NotesState.conflict ? " :: changed on disk" : "") },
            { name: "inbox", label: "inbox" }
          ]

          PanelSectionHeader {
            required property var modelData
            text: modelData.label
            foreground: (TaskState.overdueCount > 0 && modelData.name === "tasks" && root.view !== "tasks")
              || (NotesState.conflict && modelData.name === "notes") ? Colors.urgent
              : root.view === modelData.name ? Colors.accentText : Colors.textDim

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setView(parent.modelData.name)
            }
          }
        }
      }

      Item {
        anchors.top: viewTabs.bottom
        anchors.topMargin: Style.spacing.sm
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.view === "tasks"

        Item {
          id: inputLine
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.font.heading + Style.spacing.controlPaddingY * 2

          Label {
            id: inputGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(18)
            text: root.inputMode === "add" ? "+" : root.inputMode === "modify" ? "~"
              : (root.inputMode === "filter" || root.filterText ? "/" : ">")
            color: Colors.accentText
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          TextInput {
            id: input
            anchors.left: inputGlyph.right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.inputMode !== ""
            color: Colors.menu.text
            selectionColor: Style.selectionFillFor(Colors.foreground, Colors.accent)
            selectedTextColor: Style.selectionTextFor(Colors.foreground, Colors.accent)
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            clip: true

            onTextEdited: if (root.inputMode === "filter") root.filterText = text

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function (event) { event.accepted = root.inputKey(event.key, event.modifiers) }
          }

          Label {
            anchors.left: inputGlyph.right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.inputMode === "" || input.text === ""
            text: root.inputMode === "add" ? "description project:x due:tomorrow sch:mon until:eom priority:H +tag"
              : root.inputMode === "modify" && root.modifyTask ? "description project:x due:fri priority:H +tag"
              : root.inputMode === "filter" ? "filter"
              : root.filterText ? root.filterText : "add or filter"
            color: root.inputMode === "" && root.filterText ? Colors.menu.text : Colors.textDim
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          MouseArea {
            anchors.fill: parent
            visible: root.inputMode === ""
            cursorShape: Qt.IBeamCursor
            onClicked: root.startInput("add")
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Style.spacing.xxs
            color: Util.alpha(Colors.accent, root.inputMode !== "" ? Style.surface.ruleAlpha : 0.28)
          }
        }

        Label {
          id: errorLine
          anchors.top: inputLine.bottom
          anchors.topMargin: visible ? Style.spacing.xs : 0
          anchors.left: parent.left
          anchors.right: parent.right
          visible: text !== ""
          text: TaskState.errorText !== "" ? "x ERR " + TaskState.errorText : root.lastActionText
          color: TaskState.errorText !== "" ? Colors.urgentText : Colors.textDim
          caption: true
          elide: Text.ElideRight
        }

        ListView {
          id: taskList
          // the error line's own height binding loops with its elide, so the list skips it while it is hidden
          anchors.top: errorLine.visible ? errorLine.bottom : inputLine.bottom
          anchors.topMargin: Style.spacing.sm
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: timerStrip.top
          anchors.bottomMargin: timerStrip.visible ? Style.spacing.sm : 0
          model: root.filtered
          clip: true
          spacing: Style.spacing.xs
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            id: row
            required property int index
            required property var modelData

            readonly property bool hasCursor: index === root.selectedIndex && root.inputMode === ""
            readonly property bool hot: hasCursor || rowMouse.containsMouse
            // the row carries a fill: dim text on it reads as normal text
            readonly property bool lit: hot || index === root.selectedIndex

            width: ListView.view.width
            height: root.rowHeight
            radius: Style.shape.data
            opacity: panel.boot.rowOpacity(index)
            color: hasCursor ? Colors.menu.selectedBackground
              : index === root.selectedIndex || rowMouse.containsMouse ? Style.hoverFill : "transparent"
            Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.inputMode !== "") root.endInput()
                root.select(row.index)
              }
              onDoubleClicked: TaskState.markDone(row.modelData)
            }

            Label {
              id: reticle
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(12)
              text: row.hasCursor ? ">" : ""
              color: Colors.accentText
              layer.enabled: row.hasCursor && Style.fx.glow > 0
              layer.effect: Glow {}
            }

            Label {
              id: activeMark
              anchors.left: reticle.right
              anchors.leftMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(16)
              text: row.modelData.active ? "\u{f040a}" : "" // md-play
              color: Colors.ok
              icon: true
            }

            Column {
              anchors.left: activeMark.right
              anchors.leftMargin: Style.spacing.xs
              anchors.right: trailing.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter

              Label {
                width: parent.width
                text: row.modelData.desc
                color: row.hasCursor ? Colors.menu.selectedText : Colors.menu.text
                elide: Text.ElideRight
              }

              Label {
                width: parent.width
                visible: text !== ""
                text: root.metaText(row.modelData)
                dim: true
                highlighted: row.lit
                caption: true
                elide: Text.ElideRight
              }
            }

            Row {
              id: trailing
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm

              // always laid out, only shown on the hot row, so hovering never re-elides the description
              Repeater {
                model: [
                  { label: "done", act: function () { TaskState.markDone(row.modelData) } },
                  { label: row.modelData.active ? "stop" : "start", act: function () { TaskState.toggleActive(row.modelData) } },
                  { label: "del", act: function () { TaskState.remove(row.modelData) } }
                ]

                Label {
                  required property var modelData
                  opacity: row.hot ? 1 : 0
                  enabled: row.hot
                  text: "[" + modelData.label + "]"
                  color: Colors.accentText
                  caption: true
                  font.bold: true

                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.spacing.xs
                    cursorShape: Qt.PointingHandCursor
                    onClicked: parent.modelData.act()
                  }
                }
              }

              Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: row.modelData.scheduled !== ""
                text: row.modelData.scheduled
                dim: true
                highlighted: row.lit
                caption: true
              }

              Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: row.modelData.due !== ""
                text: row.modelData.due
                color: row.modelData.overdue ? Colors.urgentText : row.lit ? Colors.foreground : Colors.textDim
                caption: true
              }
            }

            HudFrame { shown: row.hasCursor }
          }

          Label {
            anchors.centerIn: parent
            visible: root.filtered.length === 0
            text: TaskState.errorText ? "> FAILED" : !TaskState.loaded ? "> LOADING" : root.filterText ? "> NO MATCH" : "> NO TASKS"
            dim: true
          }
        }

        Column {
          id: timerStrip
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: visible ? implicitHeight : 0
          visible: TimerState.pomoRunning || TimerState.reminderCount > 0 || TaskState.activeTask !== null || TaskState.trackedTotalSeconds > 0
          spacing: Style.spacing.xxs

          PanelSeparator {}

          StripLine {
            visible: TaskState.activeTask !== null
            text: TaskState.activeTask ? ("TRACKING :: " + TaskState.activeTask.desc + " " + TaskState.activeElapsedText()) : ""
            color: Colors.accentText
            elide: Text.ElideRight
          }

          StripLine {
            visible: TaskState.trackedTotalSeconds > 0
            text: "WORKTIME TODAY :: " + TaskState.totalTrackedText()
            dim: true
          }

          StripLine {
            visible: TimerState.pomoRunning
            text: "POMODORO :: " + TimerState.pomoPhaseLabel + " " + Util.clock(TimerState.pomoRemainingSeconds)
              + (TimerState.pomoPaused ? " :: PAUSED" : "")
            color: TimerState.pomo.phase === "work" ? Colors.accentText : Colors.okText
          }

          Repeater {
            // bound the strip: an unbounded reminder set would grow upward and squeeze the task list to nothing
            model: TimerState.reminders.slice(0, root.reminderShownMax)

            StripLine {
              required property var modelData
              text: "REMINDER :: " + String(modelData.label || "") + " :: " + String(modelData.atTime || "")
              color: Colors.accent2Text
              elide: Text.ElideRight
            }
          }

          StripLine {
            visible: TimerState.reminderCount > root.reminderShownMax
            text: "+" + (TimerState.reminderCount - root.reminderShownMax) + " MORE"
            dim: true
          }
        }
      }

      Flickable {
        id: notesFlick
        anchors.top: viewTabs.bottom
        anchors.topMargin: Style.spacing.sm
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.view === "notes"
        contentWidth: width
        contentHeight: Math.max(height, notesEdit.implicitHeight)
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        function ensureVisible(r) {
          if (contentY >= r.y) contentY = r.y
          else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
        }

        TextEdit {
          id: notesEdit
          width: notesFlick.width
          height: Math.max(notesFlick.height, implicitHeight)
          textFormat: TextEdit.PlainText
          color: Colors.menu.text
          selectionColor: Style.selectionFillFor(Colors.foreground, Colors.accent)
          selectedTextColor: Style.selectionTextFor(Colors.foreground, Colors.accent)
          wrapMode: TextEdit.Wrap
          selectByMouse: true
          persistentSelection: true
          font.family: Style.font.family
          font.pixelSize: Style.font.body

          Component.onCompleted: text = NotesState.text
          onTextChanged: if (activeFocus) NotesState.edit(text)
          onActiveFocusChanged: if (!activeFocus) NotesState.save()
          onCursorRectangleChanged: notesFlick.ensureVisible(cursorRectangle)

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Escape) {
              root.close()
              event.accepted = true
            } else if (NotesState.conflictKey(event.key, event.modifiers)) {
              event.accepted = true
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              root.cycleView(event.key)
              event.accepted = true
            }
          }

          Connections {
            target: NotesState
            function onTextChanged() { NotesState.syncInto(notesEdit) }
          }

          Label {
            anchors.left: parent.left
            anchors.top: parent.top
            visible: notesEdit.text.length === 0
            text: "> NO NOTES"
            dim: true
          }
        }

        MouseArea {
          anchors.fill: parent
          z: -1
          cursorShape: Qt.IBeamCursor
          onClicked: notesEdit.forceActiveFocus()
        }
      }

      // read-only: nvim (SUPER+ALT+N) edits it, the launcher appends to it
      Flickable {
        id: inboxFlick
        anchors.top: viewTabs.bottom
        anchors.topMargin: Style.spacing.sm
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.view === "inbox"
        contentWidth: width
        contentHeight: Math.max(height, inboxEdit.implicitHeight)
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        function scrollBy(dy) { contentY = Math.max(0, Math.min(contentHeight - height, contentY + dy)) }

        TextEdit {
          id: inboxEdit
          width: inboxFlick.width
          height: Math.max(inboxFlick.height, implicitHeight)
          textFormat: TextEdit.PlainText
          readOnly: true
          color: Colors.menu.text
          selectionColor: Style.selectionFillFor(Colors.foreground, Colors.accent)
          selectedTextColor: Style.selectionTextFor(Colors.foreground, Colors.accent)
          wrapMode: TextEdit.Wrap
          selectByMouse: true
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          text: inboxFile.content

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Escape) root.close()
            else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) root.cycleView(event.key)
            else if (event.key === Qt.Key_Down || event.text === "j") inboxFlick.scrollBy(root.rowHeight)
            else if (event.key === Qt.Key_Up || event.text === "k") inboxFlick.scrollBy(-root.rowHeight)
            else if (event.key === Qt.Key_PageDown) inboxFlick.scrollBy(inboxFlick.height)
            else if (event.key === Qt.Key_PageUp) inboxFlick.scrollBy(-inboxFlick.height)
            else if (event.text === "g") inboxFlick.contentY = 0
            else if (event.text === "G") inboxFlick.scrollBy(inboxFlick.contentHeight)
            else return
            event.accepted = true
          }

          Label {
            anchors.left: parent.left
            anchors.top: parent.top
            visible: inboxEdit.text.length === 0
            text: "> NO # NOTES"
            dim: true
          }
        }

        WatchedFile {
          id: inboxFile
          property string content: ""
          path: Paths.inbox
          onLoaded: content = String(text() || "")
          onLoadFailed: content = ""
        }
      }
    }
  }
}
