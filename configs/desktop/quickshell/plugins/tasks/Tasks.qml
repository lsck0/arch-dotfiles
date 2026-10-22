pragma ComponentBehavior: Bound
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null

  property string view: "tasks"
  property string inputMode: ""
  property string filterText: ""
  property int selectedIndex: 0
  property string selectedUuid: ""

  readonly property string notesPath: Paths.home + "/sync/notes/notes.md"
  property string notesDisk: ""
  property bool notesLoaded: false
  property bool notesEdited: false
  readonly property int notesSaveDelayMs: 600

  readonly property bool opened: TaskState.panelOpen
  readonly property int rowHeight: Style.space(40)

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

  readonly property var hints: view === "notes" ? [["ESC", "close"], ["TAB", "tasks"]]
    : inputMode === "add" ? [["ENTER", "add"], ["TAB", "complete +tag project: due: priority:"], ["ESC", "back"]]
    : inputMode === "filter" ? [["ENTER", "keep"], ["ESC", "clear"], ["TAB", "notes"]]
    : [["J/K", "move"], ["ENTER/D", "done"], ["S", "start/stop"], ["X", "delete"], ["A", "add"], ["/", "filter"],
       ["TAB", "notes"], ["ESC", "close"]]

  function open(payload) {
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
      root.seedNotes()
      root.focusView()
    } else {
      root.saveNotes()
      keyCatcher.forceActiveFocus()
    }
  }

  function focusView() {
    Qt.callLater(function () {
      if (root.view === "notes") notesEdit.forceActiveFocus()
      else if (root.inputMode !== "") input.forceActiveFocus()
      else keyCatcher.forceActiveFocus()
    })
  }

  function setView(name) {
    if (root.view === "notes") root.saveNotes()
    root.view = name
    if (name === "notes") root.seedNotes()
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
      } else {
        root.endInput()
      }
    } else if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
      if (key === Qt.Key_Backtab || root.inputMode !== "add" || !root.completeInput()) root.setView("notes")
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

  readonly property var fieldKeywords: ["project:", "due:", "priority:"]
  readonly property var priorities: ["H", "M", "L"]

  // a keyword already has its colon (+tag, project:x, pro:x, due:x, priority:x, prio:x): complete the value after
  // it. otherwise complete the bare word (proj, du, prio) into the keyword itself (project:, due:, priority:).
  function completeInput() {
    var head = input.text.slice(0, input.cursorPosition)
    var start = head.search(/\S*$/)
    var word = head.slice(start)
    var value = word.match(/^([+-]|pro(?:ject)?:|due:|prio(?:rity)?:)(.*)$/)
    if (value) return root.completeValue(start, value[1], value[2])
    if (!word) return false
    var field = Util.completion(word, root.fieldKeywords)
    if (field === word) return false
    input.remove(start, input.cursorPosition)
    input.insert(start, field)
    return true
  }

  // due: takes a freeform date (tomorrow, eod, 3days): nothing to complete against, stay in add mode.
  function completeValue(start, keyword, partial) {
    if (keyword === "due:") return true
    var pool = keyword.length === 1 ? root.known("tags")
      : keyword === "priority:" || keyword === "prio:" ? root.priorities
      : root.known("project")
    var done = Util.completion(partial, pool)
    var unique = pool.filter(function (c) { return c.indexOf(done) === 0 }).length === 1
    input.remove(start, input.cursorPosition)
    input.insert(start, keyword + done + (unique ? " " : ""))
    return true
  }

  function markDone(task) { if (task) TaskState.markDone(task.uuid) }
  function toggleActive(task) { if (task) TaskState.toggleActive(task.uuid, task.active) }
  function remove(task) { if (task) TaskState.remove(task.uuid) }

  function metaText(task) {
    var parts = []
    if (task.project) parts.push(task.project)
    if (task.priority) parts.push("priority:" + task.priority)
    for (let i = 0; i < task.tags.length; i++) parts.push("+" + task.tags[i])
    var tracked = TaskState.trackedText(task.desc)
    if (tracked) parts.push(tracked + " today")
    return parts.join(" ")
  }

  function seedNotes() {
    if (notesEdit.activeFocus || !root.notesLoaded) return
    if (notesEdit.text !== root.notesDisk) notesEdit.text = root.notesDisk
    root.notesEdited = false
  }

  function saveNotes() {
    saveTimer.stop()
    if (!root.notesLoaded || !root.notesEdited) return
    root.notesEdited = false
    if (notesEdit.text === root.notesDisk) return
    root.notesDisk = notesEdit.text
    notesFile.setText(notesEdit.text)
  }

  FileView {
    id: notesFile
    path: root.notesPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.notesDisk = String(text() || "")
      root.notesLoaded = true
      root.seedNotes()
      Util.rearmWatch(this)
    }
    onLoadFailed: {
      root.notesDisk = ""
      root.notesLoaded = true
      root.seedNotes()
    }
    onFileChanged: reload()
  }

  Timer {
    id: saveTimer
    interval: root.notesSaveDelayMs
    onTriggered: root.saveNotes()
  }

  IpcHandler {
    target: "tasks"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.open(null); return "ok" }
    function close(): string { root.close(); return "ok" }
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
            { name: "notes", label: "notes" }
          ]

          PanelSectionHeader {
            required property var modelData
            text: modelData.label
            foreground: TaskState.overdueCount > 0 && modelData.name === "tasks" && root.view !== "tasks" ? Colors.urgent : Colors.accent
            opacity: root.view === modelData.name ? Style.emphasis.strong : Style.emphasis.faint

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setView(parent.modelData.name)
            }
          }
        }
      }

      Item {
        id: tasksView
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

          Text {
            id: inputGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(18)
            textFormat: Text.PlainText
            text: root.inputMode === "add" ? "+" : (root.inputMode === "filter" || root.filterText ? "/" : ">")
            color: Colors.accent
            font.family: Style.font.family
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

          Text {
            anchors.left: inputGlyph.right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.inputMode === "" || input.text === ""
            textFormat: Text.PlainText
            text: root.inputMode === "add" ? "description project:x due:tomorrow priority:H +tag"
              : root.inputMode === "filter" ? "filter"
              : root.filterText ? root.filterText : "a to add, / to filter"
            color: Colors.menu.text
            opacity: root.inputMode === "" && root.filterText ? Style.emphasis.strong : Style.emphasis.faint
            font.family: Style.font.family
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

        Text {
          id: errorLine
          anchors.top: inputLine.bottom
          anchors.topMargin: visible ? Style.spacing.xs : 0
          anchors.left: parent.left
          anchors.right: parent.right
          height: visible ? implicitHeight : 0
          visible: TaskState.errorText !== ""
          textFormat: Text.PlainText
          text: "x ERR " + TaskState.errorText
          color: Colors.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        ListView {
          id: taskList
          anchors.top: errorLine.bottom
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

            Text {
              id: reticle
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(12)
              textFormat: Text.PlainText
              text: row.hasCursor ? ">" : ""
              color: Colors.menu.selectedText
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              layer.enabled: row.hasCursor && Style.fx.glow > 0
              layer.effect: Glow {}
            }

            Text {
              id: activeMark
              anchors.left: reticle.right
              anchors.leftMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(16)
              textFormat: Text.PlainText
              text: row.modelData.active ? "\u{f040a}" : "" // md-play
              color: Colors.ok
              font.family: Style.font.iconFamily
              font.pixelSize: Style.font.body
            }

            Column {
              anchors.left: activeMark.right
              anchors.leftMargin: Style.spacing.xs
              anchors.right: trailing.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: row.modelData.desc
                color: row.hasCursor ? Colors.menu.selectedText : Colors.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: text !== ""
                textFormat: Text.PlainText
                text: root.metaText(row.modelData)
                color: Colors.menu.text
                opacity: Style.emphasis.faint
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            Row {
              id: trailing
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm

              Repeater {
                model: row.hot ? [
                  { label: "done", act: function () { root.markDone(row.modelData) } },
                  { label: row.modelData.active ? "stop" : "start", act: function () { root.toggleActive(row.modelData) } },
                  { label: "del", act: function () { root.remove(row.modelData) } }
                ] : []

                Text {
                  required property var modelData
                  textFormat: Text.PlainText
                  text: "[" + modelData.label + "]"
                  color: Colors.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true

                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.spacing.xxs
                    cursorShape: Qt.PointingHandCursor
                    onClicked: parent.modelData.act()
                  }
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: row.modelData.due !== ""
                textFormat: Text.PlainText
                text: row.modelData.due
                color: row.modelData.overdue ? Colors.urgent : Colors.menu.text
                opacity: row.modelData.overdue ? Style.emphasis.strong : Style.emphasis.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            HudFrame { shown: row.hasCursor }
          }

          Text {
            anchors.centerIn: parent
            visible: root.filtered.length === 0
            textFormat: Text.PlainText
            text: !TaskState.loaded ? "> LOADING" : root.filterText ? "> NO MATCH" : "> NOTHING PENDING"
            color: Colors.menu.text
            opacity: Style.emphasis.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
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

          Text {
            width: parent.width
            visible: TaskState.activeTask !== null
            textFormat: Text.PlainText
            text: TaskState.activeTask ? ("tracking :: " + TaskState.activeTask.desc + " " + TaskState.activeElapsedText()) : ""
            color: Colors.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            visible: TaskState.trackedTotalSeconds > 0
            textFormat: Text.PlainText
            text: "worktime today :: " + TaskState.totalTrackedText()
            color: Colors.foreground
            opacity: Style.emphasis.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            visible: TimerState.pomoRunning
            textFormat: Text.PlainText
            text: "pomodoro :: " + TimerState.pomoPhaseLabel + " " + Util.clock(TimerState.pomoRemainingSeconds)
              + (TimerState.pomoPaused ? " (paused)" : "")
            color: TimerState.pomo.phase === "work" ? Colors.accent : Colors.ok
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: TimerState.reminders

            Text {
              required property var modelData
              width: parent.width
              textFormat: Text.PlainText
              text: "reminder :: " + String(modelData.label || "") + " at " + String(modelData.atTime || "")
              color: Colors.accent2
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
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

          onTextChanged: if (activeFocus) {
            root.notesEdited = true
            saveTimer.restart()
          }
          onActiveFocusChanged: if (!activeFocus) root.saveNotes()
          onCursorRectangleChanged: notesFlick.ensureVisible(cursorRectangle)

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Escape) {
              root.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              root.setView("tasks")
              event.accepted = true
            }
          }

          Text {
            anchors.left: parent.left
            anchors.top: parent.top
            visible: notesEdit.text.length === 0
            textFormat: Text.PlainText
            text: "no notes, start typing"
            color: Colors.menu.text
            opacity: Style.emphasis.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        MouseArea {
          anchors.fill: parent
          z: -1
          cursorShape: Qt.IBeamCursor
          onClicked: notesEdit.forceActiveFocus()
        }
      }
    }
  }
}
