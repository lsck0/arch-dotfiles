pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Schema.js" as Schema

Item {
  id: root

  property bool opened: false
  property bool picking: false
  property string query: ""
  property string pane: "sections"
  property int sectionIndex: 0
  property int rowIndex: -1
  property string expandedId: ""
  property int choiceCursor: -1
  property string choiceQuery: ""
  property string editingId: ""
  property string draft: ""

  property var modules: []
  property string modulesText: ""
  property bool loaded: false
  property string loadError: ""
  property var toggles: []
  property var busyToggles: ({})

  property var pending: ({})
  property var errors: ({})
  property var queue: []
  property var batch: ({ applied: [], failed: 0, notes: [] })
  property bool systemPending: false
  readonly property int exitSystemPending: 3
  // a set, apply or root toggle may ask for a polkit password, whose dialog needs the keyboard
  readonly property bool busy: setProc.running || systemApplyProc.running || toggleProc.running
  property string notice: ""

  // graphviz installs a /usr/bin/dot too, so never by PATH
  readonly property string dot: Paths.home + "/.local/bin/dot"
  readonly property var sections: Schema.sections(modules, toggles, query)
  readonly property var section: sections[Math.min(sectionIndex, sections.length - 1)] || null
  readonly property var rows: Schema.rows(modules, toggles, section ? section.id : "", query)
  readonly property var cursorRow: rowIndex >= 0 && rowIndex < rows.length ? rows[rowIndex] : null
  readonly property var choiceList: expandedId && cursorRow && cursorRow.id === expandedId
    ? Schema.choicesMatching(cursorRow.option, choiceQuery) : []
  readonly property var queued: Object.keys(pending).filter(function (id) { return pending[id].option.apply !== "live" })
  readonly property string queuedNeeds: Schema.strongestApply(queued.map(function (id) { return root.pending[id].option }))

  readonly property var hints: {
    var out = [["TYPE", root.expandedId ? "filter" : "search"], ["TAB", "pane"], ["ENTER", "edit"], ["LEFT/RIGHT", "change"],
      ["CTRL+R", "reset"]]
    if (cursorRow && cursorRow.kind === "option" && cursorRow.option.type === "path") out.push(["CTRL+O", "browse"])
    if (queued.length > 0) out.push(["CTRL+S", "apply"], ["CTRL+Z", "revert"])
    out.push(["ESC", root.editingId || root.expandedId ? "back" : root.query ? "clear" : "close"])
    return out
  }

  onExpandedIdChanged: root.choiceQuery = ""

  function open() {
    var focused = Hyprland.focusedMonitor
    panel.screen = Array.from(Quickshell.screens).find(function (s) { return focused && s.name === focused.name }) || null
    root.opened = true
    root.expandedId = ""
    root.editingId = ""
    root.notice = ""
    root.load()
    statusProc.refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.endEdit(false)
    root.expandedId = ""
    root.query = ""
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function load() {
    if (!optionsProc.running) optionsProc.running = true
  }

  function setQuery(text) {
    root.endEdit(true)
    root.expandedId = ""
    root.query = text
    root.pane = text ? "rows" : root.pane
    root.selectRow(Schema.selectable(root.rows, 0, 1))
  }

  function selectSection(index) {
    if (root.sections.length === 0) return
    root.sectionIndex = Math.max(0, Math.min(index, root.sections.length - 1))
    root.expandedId = ""
    root.selectRow(Schema.selectable(root.rows, 0, 1))
    sectionList.positionViewAtIndex(root.sectionIndex, ListView.Contain)
  }

  function enterSection(index) {
    if (root.query) root.query = ""
    root.selectSection(index)
    root.pane = "rows"
  }

  function selectRow(index) {
    if (index < 0) { root.rowIndex = Schema.selectable(root.rows, 0, 1); return }
    root.rowIndex = index
    rowList.positionViewAtIndex(index, ListView.Contain)
  }

  function moveRow(delta) {
    var direction = delta > 0 ? 1 : -1
    var start = Math.max(0, Math.min(root.rows.length - 1, root.rowIndex + delta))
    var next = Schema.selectable(root.rows, start, direction)
    if (next < 0) next = Schema.selectable(root.rows, start, -direction)
    if (next >= 0) root.selectRow(next)
  }

  function moveChoice(delta) {
    var count = root.choiceList.length
    if (count > 0) root.choiceCursor = (root.choiceCursor + delta + count) % count
  }

  function filterChoices(text) {
    root.choiceQuery = text
    root.choiceCursor = Math.max(0, root.choiceList.indexOf(root.valueOf(root.cursorRow)))
  }

  function printable(text) { return text && text.length === 1 && text.charCodeAt(0) >= 32 && text.charCodeAt(0) !== 127 }

  function handleKey(key, text, modifiers) {
    var ctrl = (modifiers & Qt.ControlModifier) !== 0
    var row = root.pane === "rows" ? root.cursorRow : null

    if (key === Qt.Key_Escape) {
      if (root.editingId) root.endEdit(false)
      else if (root.choiceQuery) root.filterChoices("")
      else if (root.expandedId) root.expandedId = ""
      else if (root.query) root.setQuery("")
      else root.close()
      return true
    }
    if (root.editingId) {
      if (key !== Qt.Key_Up && key !== Qt.Key_Down && key !== Qt.Key_Tab && key !== Qt.Key_Backtab) return false
      root.endEdit(true)
    }
    if (Util.isWordDelete(key, modifiers)) {
      if (root.expandedId) root.filterChoices(Util.wordDelete(root.choiceQuery))
      else if (root.query) root.setQuery(Util.wordDelete(root.query))
      return true
    }
    if (ctrl) {
      if (key === Qt.Key_S) root.applyQueued()
      else if (key === Qt.Key_Z) root.revertQueued()
      else if (key === Qt.Key_R && row && row.kind === "option") root.reset(row)
      else if (key === Qt.Key_O && row && row.kind === "option" && row.option.type === "path") root.browse(row)
      else return false
      return true
    }
    if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
      root.expandedId = ""
      root.pane = root.pane === "rows" ? "sections" : "rows"
      if (root.pane === "rows" && root.rowIndex < 0) root.selectRow(Schema.selectable(root.rows, 0, 1))
      return true
    }

    var vertical = key === Qt.Key_Up ? -1 : key === Qt.Key_Down ? 1 : key === Qt.Key_PageUp ? -6
      : key === Qt.Key_PageDown ? 6 : 0
    var horizontal = key === Qt.Key_Left ? -1 : key === Qt.Key_Right ? 1 : 0

    if (root.pane === "sections") {
      if (vertical !== 0) root.selectSection(root.sectionIndex + vertical)
      else if (key === Qt.Key_Right || key === Qt.Key_Return || key === Qt.Key_Enter) root.enterSection(root.sectionIndex)
      else return root.typeKey(key, text)
      return true
    }

    if (root.expandedId && row && row.id === root.expandedId) {
      if (vertical !== 0 || horizontal !== 0) root.moveChoice(vertical !== 0 ? vertical : horizontal)
      else if ((key === Qt.Key_Return || key === Qt.Key_Enter) && root.choiceList.length > 0) root.change(row, root.choiceList[root.choiceCursor])
      else if (key === Qt.Key_Backspace) root.filterChoices(root.choiceQuery.slice(0, -1))
      else if (root.printable(text)) root.filterChoices(root.choiceQuery + text)
      else return false
      return true
    }
    if (vertical !== 0) {
      root.expandedId = ""
      root.moveRow(vertical)
    } else if (horizontal !== 0) {
      if (!row || !root.adjust(row, horizontal)) {
        if (horizontal < 0) root.pane = "sections"
      }
    } else if (key === Qt.Key_Home) {
      root.selectRow(Schema.selectable(root.rows, 0, 1))
    } else if (key === Qt.Key_End) {
      root.selectRow(Schema.selectable(root.rows, root.rows.length - 1, -1))
    } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
      if (row) root.activate(row)
    } else {
      return root.typeKey(key, text)
    }
    return true
  }

  function typeKey(key, text) {
    if (key === Qt.Key_Backspace) {
      if (root.query) root.setQuery(root.query.slice(0, -1))
      return true
    }
    if (root.printable(text)) {
      root.setQuery(root.query + text)
      return true
    }
    return false
  }

  function valueOf(row) { return row.id in root.pending ? root.pending[row.id].value : row.option.value }

  function without(map, id) {
    var next = {}
    for (let k in map) if (k !== id) next[k] = map[k]
    return next
  }

  function adjust(row, direction) {
    if (row.kind === "toggle") return false
    if (row.option.type === "enum" && !Schema.segmented(row.option)) return false
    var next = Schema.adjusted(row.option, root.valueOf(row), direction)
    if (next === undefined) return false
    root.change(row, next)
    return true
  }

  function activate(row) {
    if (row.kind === "toggle") { root.runToggle(row.toggle); return }
    var option = row.option
    if (option.type === "bool") {
      root.change(row, !root.valueOf(row))
    } else if (option.type === "enum" && Schema.segmented(option)) {
      root.change(row, Schema.adjusted(option, root.valueOf(row), 1))
    } else if (option.type === "enum") {
      root.expandedId = row.id
      root.choiceCursor = Math.max(0, (option.choices || []).indexOf(root.valueOf(row)))
    } else {
      root.beginEdit(row)
    }
  }

  function beginEdit(row) {
    root.expandedId = ""
    root.rowIndex = root.rows.indexOf(row)
    root.pane = "rows"
    root.draft = Schema.toText(row.option, root.valueOf(row))
    root.editingId = row.id
  }

  function endEdit(commit) {
    if (!root.editingId) return
    var row = root.rowById(root.editingId)
    root.editingId = ""
    if (commit && row && row.option.type !== "list") {
      let value = Schema.fromText(row.option, root.draft)
      if (value !== undefined) root.change(row, value)
    }
    keyCatcher.forceActiveFocus()
  }

  function submitEdit() {
    var row = root.rowById(root.editingId)
    if (row && row.option.type === "list" && root.draft.trim() !== "") {
      root.change(row, (root.valueOf(row) || []).concat([root.draft.trim()]))
      root.draft = ""
    } else {
      root.endEdit(true)
    }
  }

  function rowById(id) { return root.rows.find(function (r) { return r.id === id }) || null }

  function change(row, value) {
    var option = row.option
    if (root.expandedId === row.id) root.expandedId = ""
    if (Schema.equal(value, root.valueOf(row)) && !(row.id in root.errors)) return
    root.errors = root.without(root.errors, row.id)
    if (option.apply !== "live" && Schema.equal(value, option.value)) {
      root.pending = root.without(root.pending, row.id)
      return
    }
    root.pending = Util.mapSet(root.pending, row.id, { value: value, option: option })
    if (option.apply === "live") root.enqueue([row.id])
  }

  function reset(row) {
    if (!Schema.resettable(row.option)) return
    root.errors = root.without(root.errors, row.id)
    root.pending = Util.mapSet(root.pending, row.id, { value: row.option.default, option: row.option, reset: true })
    if (row.option.apply === "live") root.enqueue([row.id])
  }

  function applyQueued() { root.enqueue(root.queued) }

  function revertQueued() {
    for (let i = 0; i < root.queued.length; i++) root.errors = root.without(root.errors, root.queued[i])
    var kept = {}
    for (let id in root.pending) if (root.pending[id].option.apply === "live") kept[id] = root.pending[id]
    root.pending = kept
    root.notice = ""
  }

  function browse(row) {
    root.picking = true
    pickProc.row = row
    pickProc.command = ["zenity", "--file-selection", "--filename=" + String(root.valueOf(row) || Paths.home + "/")]
    pickProc.running = true
  }

  function enqueue(ids) {
    var next = root.queue.filter(function (id) { return ids.indexOf(id) < 0 })
    root.queue = next.concat(ids)
    if (!setProc.running) root.runNext()
  }

  function runNext() {
    if (root.queue.length === 0) {
      root.finishBatch()
      return
    }
    var id = root.queue[0]
    root.queue = root.queue.slice(1)
    var entry = root.pending[id]
    if (!entry) { root.runNext(); return }
    setProc.id = id
    setProc.value = entry.value
    var option = entry.option
    // flags before `--`, so a negative number is a value and not a flag
    var machine = option.scope === "machine" ? ["--machine"] : []
    setProc.command = option.toggle ? [Paths.toggle("toggle-" + option.toggle + ".nu"), option.set, Schema.toggleArgument(option, entry.value)]
      : entry.reset ? [root.dot, "set", "--default"].concat(machine, ["--", id])
      : [root.dot, "set"].concat(machine, ["--", id, Schema.encode(option, entry.value)])
    setProc.running = true
  }

  function setDone(id, value, exitCode, message) {
    var entry = root.pending[id]
    if (!entry) return
    var current = entry.reset === true || Schema.equal(entry.value, value)
    if (exitCode === root.exitSystemPending) root.systemPending = true
    if (exitCode === 0 || exitCode === root.exitSystemPending) {
      entry.option.value = value
      if (current) root.pending = root.without(root.pending, id)
      if (entry.option.apply !== "live") root.batch.applied.push(entry.option)
    } else {
      root.errors = Util.mapSet(root.errors, id, message || "set exited with " + exitCode)
      root.batch.failed += 1
      if (entry.option.apply === "live" && current) root.pending = root.without(root.pending, id)
    }
  }

  function finishBatch() {
    var applied = root.batch.applied
    var failed = root.batch.failed
    var notes = root.batch.notes
    root.batch = { applied: [], failed: 0, notes: [] }
    root.load()
    if (applied.length === 0 && failed === 0 && notes.length === 0) return
    var parts = []
    if (applied.length > 0) {
      let needs = Schema.strongestApply(applied)
      parts.push("applied " + applied.length
        + (needs === "relogin" ? ", log out and back in to finish" : needs === "reboot" ? ", reboot to finish" : ""))
    }
    if (failed > 0) parts.push(failed + " failed, see the marked options")
    root.notice = parts.concat(notes).join("; ")
  }

  function runToggle(toggle) {
    if (toggleProc.running) return
    root.busyToggles = Util.mapSet(root.busyToggles, toggle.name, true)
    toggleProc.command = [Paths.toggle("toggle-" + toggle.name + ".nu"), "toggle"]
    toggleProc.running = true
  }

  Process {
    id: optionsProc
    command: [root.dot, "set", "--json"]
    stdout: StdioCollector { id: optionsOut; waitForEnd: true }
    stderr: StdioCollector { id: optionsErr; waitForEnd: true }
    onExited: function (exitCode) {
      var data = null
      try { data = JSON.parse(optionsOut.text) } catch (e) { data = null }
      if (exitCode !== 0 || !data || !Array.isArray(data.modules)) {
        root.loadError = String(optionsErr.text || "").trim().split("\n")[0] || "dot set --json exited with " + exitCode
        return
      }
      root.loadError = ""
      root.loaded = true
      if (optionsOut.text === root.modulesText) return
      root.modulesText = optionsOut.text
      root.modules = data.modules.map(Schema.moduleNormalize)
      if (root.rowIndex < 0 || root.rowIndex >= root.rows.length) root.selectRow(Schema.selectable(root.rows, 0, 1))
      else root.selectRow(root.rowIndex)
      sectionList.positionViewAtIndex(root.sectionIndex, ListView.Contain)
    }
  }

  Process {
    id: setProc
    property string id: ""
    property var value
    stdout: StdioCollector { id: setOut; waitForEnd: true }
    stderr: StdioCollector { id: setErr; waitForEnd: true }
    onExited: function (exitCode) {
      root.batch.notes = root.batch.notes.concat(Schema.notes(setErr.text)).concat(Schema.notes(setOut.text))
      root.setDone(setProc.id, setProc.value, exitCode, String(setErr.text || setOut.text || "").trim().split("\n").pop())
      root.runNext()
    }
  }

  Process {
    id: systemApplyProc
    command: [root.dot, "apply"]
    stdout: StdioCollector { id: applyOut; waitForEnd: true }
    stderr: StdioCollector { id: applyErr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode === 0) root.systemPending = false
      root.notice = exitCode === 0 ? ["system part applied"].concat(Schema.notes(applyErr.text)).concat(Schema.notes(applyOut.text)).join("; ")
        : "apply failed: " + String(applyErr.text || applyOut.text || "").trim().split("\n").pop()
      root.load()
    }
  }

  // a toggle that fails never announces itself, so its exit clears the busy mark
  Process {
    id: toggleProc
    onExited: statusProc.refresh()
  }

  Process {
    id: pickProc
    property var row: null
    stdout: StdioCollector { id: pickOut; waitForEnd: true }
    onExited: function (exitCode) {
      root.picking = false
      var path = String(pickOut.text || "").trim()
      if (exitCode === 0 && path && pickProc.row) root.change(pickProc.row, path)
      Qt.callLater(function () { keyCatcher.forceActiveFocus() })
    }
  }

  JsonProcess {
    id: statusProc
    command: [Paths.toggle("status.nu"), "--options"]
    onParsed: function (data) {
      root.busyToggles = ({})
      var next = Array.from(data || [])
      if (!Schema.equal(next, root.toggles)) root.toggles = next
    }
  }

  Connections {
    target: ToggleEvents
    function onChanged(script) { if (root.opened) statusProc.refresh() }
  }

  IpcHandler {
    target: "settings"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
  }

  OverlayCard {
    id: panel
    open: root.opened && !root.picking
    name: "settings"
    title: "settings"
    prompt: true
    query: root.query
    placeholder: "search settings"
    hints: root.hints
    keyboard: !root.busy
    cardWidth: Style.space(960)
    cardHeight: Style.space(640)
    onDismissed: root.close()

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function (event) { event.accepted = root.handleKey(event.key, event.text, event.modifiers) }

      ListView {
        id: sectionList
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: Style.space(200)
        model: root.sections
        clip: true
        spacing: Style.spacing.xxs
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Rectangle {
          id: sectionRow
          required property var modelData
          required property int index

          readonly property bool current: index === root.sectionIndex && !root.query
          readonly property bool hasCursor: current && root.pane === "sections"
          readonly property bool hasPending: Object.keys(root.pending).some(function (id) {
            return id.indexOf(sectionRow.modelData.id + ".") === 0
          })

          width: ListView.view.width
          height: Style.row.list
          radius: Style.shape.data
          opacity: root.query && modelData.count === 0 ? Style.emphasis.disabled : 1
          color: hasCursor ? Colors.menu.selectedBackground : current || sectionMouse.containsMouse ? Style.hoverFill : "transparent"

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.right: count.left
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: (sectionRow.hasCursor ? "> " : "") + sectionRow.modelData.label + (sectionRow.hasPending ? " *" : "")
            color: sectionRow.current ? Colors.menu.selectedText : Colors.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: sectionRow.current
            elide: Text.ElideRight
          }

          Text {
            id: count
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String(sectionRow.modelData.count)
            color: Colors.menu.text
            opacity: Style.emphasis.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: sectionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.enterSection(sectionRow.index)
          }
        }
      }

      Rectangle {
        id: divider
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: sectionList.right
        anchors.leftMargin: Style.spacing.md
        width: Style.normalBorderWidth
        color: Util.alpha(Colors.menu.border, 0.28)
      }

      Item {
        id: main
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: divider.right
        anchors.leftMargin: Style.spacing.md
        anchors.right: parent.right

        Text {
          id: sourceLine
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          bottomPadding: Style.spacing.sm
          visible: text !== ""
          textFormat: Text.PlainText
          text: root.loadError ? "x " + root.loadError : ""
          color: root.loadError ? Colors.urgent : Colors.warn
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        ListView {
          id: rowList
          anchors.top: sourceLine.visible ? sourceLine.bottom : parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: pendingBar.top
          anchors.bottomMargin: pendingBar.visible ? Style.spacing.sm : 0
          model: root.rows
          clip: true
          spacing: Style.spacing.xxs
          boundsBehavior: Flickable.StopAtBounds

          delegate: Item {
            id: slot
            required property var modelData
            required property int index

            readonly property bool hasCursor: root.pane === "rows" && index === root.rowIndex

            width: ListView.view.width
            height: loader.height

            Loader {
              id: loader
              width: parent.width
              sourceComponent: slot.modelData.kind === "header" ? headerRow
                : slot.modelData.kind === "toggle" ? toggleRow : optionRow
            }

            Component {
              id: headerRow
              PanelSectionHeader {
                text: slot.modelData.text
                topPadding: slot.index > 0 ? Style.spacing.md : Math.ceil(fontSize * 0.15)
              }
            }

            Component {
              id: toggleRow
              Rectangle {
                readonly property var toggle: slot.modelData.toggle
                readonly property bool busy: root.busyToggles[toggle.name] === true

                implicitHeight: Style.row.list
                radius: Style.shape.data
                color: slot.hasCursor ? Colors.menu.selectedBackground : toggleMouse.containsMouse ? Style.hoverFill : "transparent"

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.md
                  anchors.right: toggleState.left
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: (slot.hasCursor ? "> " : "  ") + parent.toggle.label
                  color: slot.hasCursor ? Colors.menu.selectedText : Colors.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                ToggleSwitch {
                  id: toggleState
                  visible: !Schema.toggleCycles(parent.toggle) && !parent.busy
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  checked: parent.toggle.on
                  interactive: false
                  hasCursor: slot.hasCursor
                }

                Text {
                  visible: Schema.toggleCycles(parent.toggle) || parent.busy
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: parent.busy ? "..." : "[next]"
                  color: Colors.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                MouseArea {
                  id: toggleMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.pane = "rows"
                    root.rowIndex = slot.index
                    root.runToggle(parent.toggle)
                  }
                }
              }
            }

            Component {
              id: optionRow
              OptionRow {
                option: slot.modelData.option
                value: root.valueOf(slot.modelData)
                pending: slot.modelData.id in root.pending
                error: root.errors[slot.modelData.id] || ""
                hasCursor: slot.hasCursor
                expanded: root.expandedId === slot.modelData.id
                choiceCursor: root.choiceCursor
                listed: root.expandedId === slot.modelData.id ? root.choiceList : []
                choiceFilter: root.expandedId === slot.modelData.id ? root.choiceQuery : ""
                editing: root.editingId === slot.modelData.id
                draft: root.draft

                onSelectRequested: { root.pane = "rows"; root.rowIndex = slot.index }
                onChangeRequested: function (picked) { root.change(slot.modelData, picked) }
                onResetRequested: root.reset(slot.modelData)
                onEditRequested: root.beginEdit(slot.modelData)
                onDraftEdited: function (text) { root.draft = text }
                onSubmitted: root.submitEdit()
                onExpandRequested: {
                  root.pane = "rows"
                  root.rowIndex = slot.index
                  if (root.expandedId === slot.modelData.id) root.expandedId = ""
                  else root.activate(slot.modelData)
                }
                onBrowseRequested: root.browse(slot.modelData)
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.rows.length === 0
            textFormat: Text.PlainText
            text: !root.loaded && !root.loadError ? "> LOADING" : root.query ? "> NO MATCH" : "> NOTHING HERE"
            color: Colors.menu.text
            opacity: Style.emphasis.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        Column {
          id: pendingBar
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          visible: root.queued.length > 0 || root.notice !== "" || root.systemPending
          spacing: Style.spacing.xs

          PanelSeparator {}

          Item {
            width: parent.width
            height: visible ? applyButton.implicitHeight : 0
            visible: root.queued.length > 0

            Text {
              anchors.left: parent.left
              anchors.right: buttons.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.queued.length + (root.queued.length === 1 ? " change" : " changes") + " pending"
                + (root.queuedNeeds ? ", needs " + root.queuedNeeds : "")
              color: Colors.accent2
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Row {
              id: buttons
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm

              Button {
                text: "revert"
                bordered: true
                onClicked: root.revertQueued()
              }

              Button {
                id: applyButton
                text: setProc.running ? "applying" : "apply"
                bordered: true
                selected: true
                onClicked: root.applyQueued()
              }
            }
          }

          Item {
            width: parent.width
            height: visible ? systemApplyButton.implicitHeight : 0
            visible: root.systemPending

            Text {
              anchors.left: parent.left
              anchors.right: systemApplyButton.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "saved, the system part needs apply"
              color: Colors.warn
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Button {
              id: systemApplyButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: systemApplyProc.running ? "applying" : "apply system"
              bordered: true
              selected: true
              onClicked: if (!systemApplyProc.running) systemApplyProc.running = true
            }
          }

          Text {
            width: parent.width
            visible: root.notice !== ""
            textFormat: Text.PlainText
            text: root.notice
            color: root.notice.indexOf("failed") >= 0 ? Colors.urgent : Colors.ok
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }
        }
      }
    }
  }
}
