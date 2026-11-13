pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  property string view: "tasks"
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
    var list = TaskState.tasks || []
    var needle = root.filterText.trim().toLowerCase()
    var out = []
    for (let i = 0; i < list.length; i++) {
      let t = list[i]
      if (needle) {
        let hay = (t.desc + " " + t.project + " " + t.tags.join(" ")).toLowerCase()
        if (hay.indexOf(needle) < 0) continue
      }
      out.push(t)
    }
    return out
  }

  readonly property var selectedTask: filtered.length > 0 && selectedIndex >= 0 && selectedIndex < filtered.length
    ? filtered[selectedIndex] : null

  readonly property var hints: view === "notes" && NotesState.conflict
    ? [["CTRL+S", "overwrite disk"], ["CTRL+R", "take disk"], ["TAB", "inbox"], ["ESC", "close"]]
    : view === "notes" ? [["TAB", "inbox"], ["ESC", "close"]]
    : view === "inbox" ? [["^/v", "scroll"], ["TAB", "tasks"], ["ESC", "close"]]
    : inputMode === "add" ? [["ENTER", "add"], ["TAB", "complete +tag project: due: scheduled: priority:"], ["ESC", "back"]]
    : inputMode === "modify" ? [["ENTER", "modify"], ["TAB", "complete +tag -tag project: due: priority:"], ["ESC", "back"]]
    : inputMode === "filter" ? [["ENTER", "keep"], ["TAB", "notes"], ["ESC", "clear"]]
    : [["^/v", "move"], ["ENTER/D", "done"], ["S", "start/stop"], ["X", "delete"], ["E", "edit"], ["U", "undo"],
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
    input.text = mode === "filter" ? root.filterText : ""
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
      root.setView("notes")
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
      root.markDone(root.selectedTask)
    } else if (text === "s") {
      root.toggleActive(root.selectedTask)
    } else if (key === Qt.Key_Delete || text === "x") {
      root.remove(root.selectedTask)
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
      else root.setView("notes")
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

  readonly property var fieldKeywords: ["project:", "due:", "scheduled:", "wait:", "priority:", "recur:"]
  readonly property var freeformKeywords: ["due:", "sch:", "scheduled:", "wait:", "recur:"]
  readonly property var priorities: ["H", "M", "L"]

  // after a keyword's colon complete its value, else complete the bare word into the keyword
  function completeInput() {
    var head = input.text.slice(0, input.cursorPosition)
    var start = head.search(/\S*$/)
    var word = head.slice(start)
    var value = word.match(/^([+-]|pro(?:ject)?:|due:|sch(?:eduled)?:|wait:|recur:|prio(?:rity)?:)(.*)$/)
    if (value) return root.completeValue(start, value[1], value[2])
    if (!word) return false
    var field = Util.completion(word, root.fieldKeywords)
    if (field === word) return false
    input.remove(start, input.cursorPosition)
    input.insert(start, field)
    return true
  }

  // due:, scheduled:, wait: and recur: take a freeform date or period (tomorrow, eod, 3days, weekly): nothing to
  // complete against, stay in add mode.
  function completeValue(start, keyword, partial) {
    if (root.freeformKeywords.indexOf(keyword) >= 0) return true
    var pool = keyword.length === 1 ? root.known("tags")
      : keyword === "priority:" || keyword === "prio:" ? root.priorities
      : root.known("project")
    var done = Util.completion(partial, pool)
    var unique = pool.filter(function (c) { return c.indexOf(done) === 0 }).length === 1
    input.remove(start, input.cursorPosition)
    input.insert(start, keyword + done + (unique ? " " : ""))
    return true
  }

  function markDone(task) { TaskState.markDone(task) }
  function toggleActive(task) { TaskState.toggleActive(task) }
  function remove(task) { TaskState.remove(task) }

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
            selectedTextColor: Colors.menu.text
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
            text: root.inputMode === "add" ? "description project:x due:tomorrow priority:H +tag"
              : root.inputMode === "modify" && root.modifyTask ? "new description or due:fri priority:H -tag :: " + root.modifyTask.desc
              : root.inputMode === "filter" ? "filter"
              : root.filterText ? root.filterText : "a to add, / to filter"
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

            width: ListView.view.width
            height: root.rowHeight
            radius: Style.shape.data
            opacity: panel.boot.rowOpacity(index)
            color: hasCursor ? Colors.menu.selectedBackground
              : index === root.selectedIndex || rowMouse.containsMouse ? Style.hoverFill : "transparent"

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.inputMode !== "") root.endInput()
                root.select(row.index)
              }
              onDoubleClicked: root.markDone(row.modelData)
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
                  { label: "done", act: function () { root.markDone(row.modelData) } },
                  { label: row.modelData.active ? "stop" : "start", act: function () { root.toggleActive(row.modelData) } },
                  { label: "del", act: function () { root.remove(row.modelData) } }
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
                color: Colors.textDim
                caption: true
              }

              Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: row.modelData.due !== ""
                text: row.modelData.due
                color: row.modelData.overdue ? Colors.urgentText : Colors.textDim
                caption: true
              }
            }

            HudFrame { shown: row.hasCursor }
          }

          Label {
            anchors.centerIn: parent
            visible: root.filtered.length === 0
            text: TaskState.errorText ? "> FAILED" : !TaskState.loaded ? "> LOADING" : root.filterText ? "> NO MATCH" : "> NOTHING PENDING"
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
            text: TaskState.activeTask ? ("tracking :: " + TaskState.activeTask.desc + " " + TaskState.activeElapsedText()) : ""
            color: Colors.accentText
            elide: Text.ElideRight
          }

          StripLine {
            visible: TaskState.trackedTotalSeconds > 0
            text: "worktime today :: " + TaskState.totalTrackedText()
            dim: true
          }

          StripLine {
            visible: TimerState.pomoRunning
            text: "pomodoro :: " + TimerState.pomoPhaseLabel + " " + Util.clock(TimerState.pomoRemainingSeconds)
              + (TimerState.pomoPaused ? " (paused)" : "")
            color: TimerState.pomo.phase === "work" ? Colors.accentText : Colors.okText
          }

          Repeater {
            // bound the strip: an unbounded reminder set would grow upward and squeeze the task list to nothing
            model: TimerState.reminders.slice(0, root.reminderShownMax)

            StripLine {
              required property var modelData
              text: "reminder :: " + String(modelData.label || "") + " at " + String(modelData.atTime || "")
              color: Colors.accent2Text
              elide: Text.ElideRight
            }
          }

          StripLine {
            visible: TimerState.reminderCount > root.reminderShownMax
            text: "+" + (TimerState.reminderCount - root.reminderShownMax) + " more reminders"
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
          selectedTextColor: Colors.menu.text
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
              root.setView("inbox")
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
            text: "no notes, start typing"
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
          selectedTextColor: Colors.menu.text
          wrapMode: TextEdit.Wrap
          selectByMouse: true
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          text: inboxFile.content

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Escape) root.close()
            else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) root.setView("tasks")
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
            text: "no # notes yet"
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
