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
  property var dotStatus: null
  property var driftChoice: ({})
  property string confirmId: ""

  property var pending: ({})
  property var errors: ({})
  property var queue: []
  property var batch: ({ applied: [], failed: 0, notes: [] })
  property bool systemPending: false
  readonly property int exitSystemPending: 3
  readonly property bool busy: setProc.running || systemApplyProc.running || toggleProc.running || systemProc.running
  property string notice: ""
  property bool noticeIsError: false
  property bool updateArmed: false

  readonly property string dot: Paths.home + "/.local/bin/dot"
  readonly property var sections: Schema.sections(modules, toggles, query, dotStatus)
  // room beside each list for its scroll bar, kept when the list fits so the rows never jump
  readonly property int barGutter: Style.spacing.xs + Style.spacing.xxs * 3
  readonly property var section: sections[Math.min(sectionIndex, sections.length - 1)] || null
  readonly property var rows: Schema.rows(modules, toggles, section ? section.id : "", query, dotStatus)
  readonly property var cursorRow: rowIndex >= 0 && rowIndex < rows.length ? rows[rowIndex] : null
  readonly property var choiceList: expandedId && cursorRow && cursorRow.id === expandedId
    ? Schema.choicesMatching(cursorRow.option, choiceQuery) : []
  readonly property var queued: Object.keys(pending).filter(function (id) { return pending[id].option.apply !== "live" })
  readonly property string queuedNeeds: Schema.strongestApply(queued.map(function (id) { return root.pending[id].option }))

  readonly property var hints: {
    var out = [["TYPE", root.expandedId ? "filter" : "search"], ["TAB", "pane"], ["ENTER", "edit"], ["</>", "change"],
      ["CTRL+R", "reset"]]
    if (cursorRow && cursorRow.kind === "option" && cursorRow.option.type === "path") out.push(["CTRL+O", "browse"])
    if (queued.length > 0) out.push(["CTRL+S", "apply"], ["CTRL+Z", "revert"])
    out.push(["CTRL+U", root.updateArmed ? "confirm sync" : "update"])
    out.push(["ESC", root.editingId || root.expandedId ? "back" : root.query ? "clear" : "close"])
    return out
  }

  onExpandedIdChanged: root.choiceQuery = ""
  onRowIndexChanged: root.confirmId = ""

  function open(output) {
    var name = output || (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")
    panel.screen = Array.from(Quickshell.screens).find(function (s) { return s.name === name }) || null
    root.opened = true
    root.expandedId = ""
    root.editingId = ""
    root.notice = ""
    root.noticeIsError = false
    root.updateArmed = false
    root.load()
    statusProc.refresh()
    dotStatusProc.refresh()
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

  function selectSection(index, direction) {
    if (root.sections.length === 0) return
    var dir = direction || 1
    var start = Math.max(0, Math.min(index, root.sections.length - 1))
    var next = Schema.selectable(root.sections, start, dir)
    if (next < 0) next = Schema.selectable(root.sections, start, -dir)
    if (next < 0) return
    root.sectionIndex = next
    root.expandedId = ""
    root.selectRow(Schema.selectable(root.rows, 0, 1))
    root.reveal(sectionList, sectionFade, root.sectionIndex)
  }

  function enterSection(index) {
    if (root.query) root.query = ""
    root.selectSection(index)
    root.pane = "rows"
  }

  function selectRow(index) {
    if (index < 0) { root.rowIndex = Schema.selectable(root.rows, 0, 1); return }
    root.rowIndex = index
    root.reveal(rowList, rowFade, index)
  }

  // the overflow fade covers the bottom row: scroll the cursor row above it, unless that runs past the end
  function reveal(list, fade, index) {
    list.positionViewAtIndex(index, ListView.Contain)
    var item = list.itemAtIndex(index)
    if (!item || !fade.overflows) return
    var over = item.y + item.height - (list.contentY + list.height - fade.reach)
    if (over > 0) list.contentY = Math.min(list.contentY + over, list.originY + list.contentHeight - list.height)
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

  function update() { root.runSystem(Object.assign({ kind: "action" }, Schema.systemActions[0]), "") }

  // Ctrl+U runs a full sync; arm on the first press and run on the second, so one stray keystroke never starts one
  function armOrUpdate() {
    if (root.updateArmed) {
      root.updateArmed = false;
      updateDisarm.stop();
      root.update();
      return;
    }
    root.updateArmed = true;
    root.notice = "press CTRL+U again to sync";
    root.noticeIsError = false;
    updateDisarm.restart();
  }

  Timer {
    id: updateDisarm

    interval: 3000
    onTriggered: {
      root.updateArmed = false;
      if (root.notice === "press CTRL+U again to sync")
        root.notice = "";
    }
  }

  function choiceOf(row) { return root.driftChoice[row.id] || Schema.driftChoices[0] }

  // a terminal action leaves the window for its terminal; reset overwrites a hand edit, so it asks twice
  function runSystem(row, choice) {
    if (row.kind === "drift" && choice === "reset" && root.confirmId !== row.id) {
      root.confirmId = row.id
      return
    }
    root.confirmId = ""
    var argv = Schema.systemCommand(root.dot, row, choice)
    if (row.terminal) {
      Quickshell.execDetached(Schema.terminalCommand(argv, argv.slice(1).join(" ")))
      root.close()
      return
    }
    if (systemProc.running) return
    systemProc.label = row.kind === "drift" ? choice + " " + row.target : row.name
    systemProc.command = argv
    systemProc.running = true
  }

  function handleKey(key, text, modifiers) {
    var ctrl = (modifiers & Qt.ControlModifier) !== 0
    var row = root.pane === "rows" ? root.cursorRow : null

    if (key === Qt.Key_Escape) {
      if (root.confirmId) root.confirmId = ""
      else if (root.editingId) root.endEdit(false)
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
      else if (key === Qt.Key_U) root.armOrUpdate()
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
      if (vertical !== 0) root.selectSection(root.sectionIndex + vertical, vertical > 0 ? 1 : -1)
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
    if (row.kind === "drift") {
      let at = Schema.driftChoices.indexOf(root.choiceOf(row))
      let n = Schema.driftChoices.length
      root.driftChoice = Util.mapSet(root.driftChoice, row.id, Schema.driftChoices[(at + direction + n) % n])
      root.confirmId = ""
      return true
    }
    if (row.kind !== "option") return false
    if (row.option.type === "enum" && !Schema.segmented(row.option)) return false
    var next = Schema.adjusted(row.option, root.valueOf(row), direction)
    if (next === undefined) return false
    root.change(row, next)
    return true
  }

  function activate(row) {
    if (row.kind === "toggle") { root.runToggle(row.toggle); return }
    if (row.kind === "action" || row.kind === "drift") { root.runSystem(row, root.choiceOf(row)); return }
    if (row.kind !== "option") return
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
    root.noticeIsError = false
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
    root.noticeIsError = failed > 0
  }

  function runToggle(toggle) {
    if (toggleProc.running) return
    root.busyToggles = Util.mapSet(root.busyToggles, toggle.name, true)
    toggleProc.command = ["uwsm-app", "-s", "b", "--", Paths.toggle("toggle-" + toggle.name + ".nu"), "toggle"]
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
      var at = root.sections[root.sectionIndex]
      if (at && at.kind === "header") root.selectSection(root.sectionIndex)
      else root.reveal(sectionList, sectionFade, root.sectionIndex)
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
    command: [root.dot, "apply", "--system"]
    stdout: StdioCollector { id: applyOut; waitForEnd: true }
    stderr: StdioCollector { id: applyErr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode === 0) root.systemPending = false
      root.notice = exitCode === 0 ? ["system part applied"].concat(Schema.notes(applyErr.text)).concat(Schema.notes(applyOut.text)).join("; ")
        : "apply failed: " + String(applyErr.text || applyOut.text || "").trim().split("\n").pop()
      root.noticeIsError = exitCode !== 0
      root.load()
    }
  }

  Process {
    id: systemProc
    property string label: ""
    stdout: StdioCollector { id: systemOut; waitForEnd: true }
    stderr: StdioCollector { id: systemErr; waitForEnd: true }
    onExited: function (exitCode) {
      var last = String(systemErr.text || systemOut.text || "").trim().split("\n").pop()
      root.notice = exitCode === 0 || exitCode === root.exitSystemPending
        ? [systemProc.label + " done"].concat(Schema.notes(systemErr.text)).concat(Schema.notes(systemOut.text)).join("; ")
        : systemProc.label + " failed: " + last
      root.noticeIsError = !(exitCode === 0 || exitCode === root.exitSystemPending)
      root.load()
      dotStatusProc.run()
    }
  }

  JsonProcess {
    id: dotStatusProc
    command: [root.dot, "status", "--json"]
    onParsed: function (data) {
      if (Schema.equal(data, root.dotStatus)) return
      // the first answer adds the System section, which would shift the cursor onto the section above it
      var id = root.section ? root.section.id : ""
      root.dotStatus = data
      var at = root.sections.findIndex(function (s) { return s.id === id })
      if (at >= 0) root.sectionIndex = at
      if (root.rowIndex < 0 || root.rowIndex >= root.rows.length) root.selectRow(Schema.selectable(root.rows, 0, 1))
    }
  }

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
    function open(): string { root.open(""); return "ok" }
    function openOn(output: string): string { root.open(output); return "ok" }
    function close(): string { root.close(); return "ok" }
  }

  // an overflowing list keeps its bar on screen at rest, not only while it scrolls. It sits in the gutter beside
  // the list, out of its faded layer and clear of the cursor row
  component ListScrollBar: ScrollBar {
    id: scrollBar
    required property ListView list

    parent: list.parent
    anchors.top: list.top
    anchors.bottom: list.bottom
    anchors.left: list.right
    anchors.leftMargin: Style.spacing.xxs
    policy: size < 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
    padding: Style.spacing.xxs
    minimumSize: 0.1
    background: Rectangle {
      implicitWidth: Style.spacing.xs + Style.spacing.xxs * 2
      radius: width / 2
      color: Util.alpha(Colors.menu.text, Style.hoverFillAlpha)
    }
    contentItem: Rectangle {
      implicitWidth: Style.spacing.xs
      radius: width / 2
      color: scrollBar.active || scrollBar.hovered ? Colors.menu.text : Colors.textDim
    }
  }

  // alpha mask fading the last visible row of an overflowing list until it reaches its end
  component ListFade: Item {
    id: fade
    required property ListView list
    readonly property bool overflows: list.contentHeight > list.height + 1
    readonly property real reach: Style.row.list
    property real strength: list.atYEnd ? 0 : 1

    anchors.fill: list
    visible: false
    layer.enabled: overflows
    Behavior on strength { NumberAnimation { duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0.0; color: "black" }
        GradientStop { position: Math.max(0, 1 - fade.reach / Math.max(1, fade.height)); color: "black" }
        GradientStop { position: 1.0; color: Util.alpha("black", 1 - 0.95 * fade.strength) }
      }
    }
  }

  // a list masked by its ListFade while it overflows
  component FadedList: ListView {
    id: fadedList
    required property ListFade fade

    layer.enabled: fade.overflows
    layer.effect: FadeMask { maskSource: fadedList.fade }
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

      FadedList {
        id: sectionList
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: Style.space(200) - root.barGutter
        model: root.sections
        clip: true
        spacing: Style.spacing.xxs
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ListScrollBar { list: sectionList }
        fade: sectionFade

        delegate: Rectangle {
          id: sectionRow
          required property var modelData
          required property int index

          readonly property bool header: modelData.kind === "header"
          readonly property bool current: !header && index === root.sectionIndex && !root.query
          readonly property bool hasCursor: current && root.pane === "sections"
          readonly property bool hasPending: Object.keys(root.pending).some(function (id) {
            return id.indexOf(sectionRow.modelData.id + ".") === 0
          })

          width: ListView.view.width
          height: header ? Style.row.list * 0.8 + (index > 1 ? Style.spacing.sm : 0) : Style.row.list
          radius: Style.shape.data
          opacity: root.query && !header && modelData.count === 0 ? Style.emphasis.disabled : 1
          color: header ? "transparent" : hasCursor ? Colors.menu.selectedBackground
            : current || sectionMouse.containsMouse ? Style.hoverFill : "transparent"

          Rectangle {
            visible: sectionRow.current
            width: Style.selectedBorderWidth
            height: parent.height
            color: Style.selectedMarkColor(Colors.menu.text, Colors.accent)
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.right: count.left
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: sectionRow.header ? undefined : parent.verticalCenter
            anchors.bottom: sectionRow.header ? parent.bottom : undefined
            textFormat: Text.PlainText
            text: sectionRow.header ? sectionRow.modelData.label.toUpperCase()
              : (sectionRow.hasCursor ? "> " : "") + sectionRow.modelData.label + (sectionRow.hasPending ? " *" : "")
            color: sectionRow.header ? Colors.textDim : sectionRow.current ? Colors.menu.selectedText : Colors.menu.text
            font.family: Style.font.family
            font.pixelSize: sectionRow.header ? Style.font.caption : Style.font.body
            font.bold: sectionRow.current || sectionRow.header
            font.letterSpacing: sectionRow.header ? Style.space(1) : 0
            elide: Text.ElideRight
          }

          Text {
            id: count
            visible: !sectionRow.header
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String(sectionRow.modelData.count)
            color: Colors.textDim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: sectionMouse
            anchors.fill: parent
            enabled: !sectionRow.header
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.enterSection(sectionRow.index)
          }
        }
      }

      ListFade {
        id: sectionFade
        list: sectionList
      }

      Rectangle {
        id: divider
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: sectionList.right
        anchors.leftMargin: root.barGutter + Style.spacing.md
        width: Style.normalBorderWidth
        color: Util.alpha(Colors.menu.border, 0.28)
      }

      Item {
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
          color: Colors.urgentText
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        FadedList {
          id: rowList
          anchors.top: sourceLine.visible ? sourceLine.bottom : parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.rightMargin: root.barGutter
          anchors.bottom: pendingBar.top
          anchors.bottomMargin: pendingBar.visible ? Style.spacing.sm : 0
          model: root.rows
          clip: true
          spacing: Style.spacing.xxs
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ListScrollBar { list: rowList }
          fade: rowFade

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
                : slot.modelData.kind === "toggle" ? toggleRow
                : slot.modelData.kind === "check" ? checkRow
                : slot.modelData.kind === "action" ? actionRow
                : slot.modelData.kind === "drift" ? driftRow : optionRow
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
                readonly property bool isSwitch: Schema.toggleIsSwitch(toggle)

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

                Toggle {
                  id: toggleState
                  visible: parent.isSwitch && !parent.busy
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  checked: parent.toggle.on
                  interactive: false
                  hasCursor: slot.hasCursor
                }

                Text {
                  visible: !parent.isSwitch || parent.busy
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: parent.busy ? "..." : "[" + String(parent.toggle.text).toLowerCase() + "]"
                  color: parent.toggle.state === "error" ? Colors.urgentText : Colors.accentText
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
              id: checkRow
              Rectangle {
                readonly property var check: slot.modelData
                readonly property color levelColor: check.level === "FAIL" ? Colors.urgentText
                  : check.level === "WARN" || check.level === "pending" ? Colors.warnText
                  : check.level === "ok" ? Colors.okText : Colors.accentText

                implicitHeight: Math.max(Style.row.list, checkText.implicitHeight + Style.spacing.sm * 2)
                radius: Style.shape.data
                color: slot.hasCursor ? Colors.menu.selectedBackground : "transparent"

                Text {
                  id: checkLevel
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.md
                  anchors.top: parent.top
                  anchors.topMargin: Style.spacing.sm
                  width: Style.space(70)
                  textFormat: Text.PlainText
                  text: (slot.hasCursor ? "> " : "  ") + "[" + parent.check.level.toLowerCase() + "]"
                  color: parent.levelColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Text {
                  id: checkText
                  anchors.left: checkLevel.right
                  anchors.leftMargin: Style.spacing.sm
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.md
                  anchors.top: parent.top
                  anchors.topMargin: Style.spacing.sm
                  textFormat: Text.PlainText
                  text: parent.check.name + ": " + parent.check.text
                  color: slot.hasCursor ? Colors.menu.selectedText : Colors.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  wrapMode: Text.Wrap
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: { root.pane = "rows"; root.rowIndex = slot.index }
                }
              }
            }

            Component {
              id: actionRow
              PanelRow {
                upper: false
                label: (slot.hasCursor ? "> " : "  ") + slot.modelData.name
                trailing: slot.modelData.detail + (slot.modelData.terminal ? "  [terminal]" : "")
                on: slot.hasCursor
                enabled: !systemProc.running
                onActivated: {
                  root.pane = "rows"
                  root.rowIndex = slot.index
                  root.runSystem(slot.modelData, "")
                }
              }
            }

            Component {
              id: driftRow
              Rectangle {
                id: drift
                readonly property var entry: slot.modelData
                readonly property string choice: root.choiceOf(entry)
                readonly property bool confirming: root.confirmId === entry.id

                implicitHeight: driftColumn.implicitHeight + Style.spacing.sm * 2
                radius: Style.shape.data
                color: slot.hasCursor ? Colors.menu.selectedBackground : driftMouse.containsMouse ? Style.hoverFill : "transparent"

                MouseArea {
                  id: driftMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: { root.pane = "rows"; root.rowIndex = slot.index }
                }

                Text {
                  id: driftCursor
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.md
                  anchors.top: driftColumn.top
                  textFormat: Text.PlainText
                  text: slot.hasCursor ? "> " : "  "
                  color: Colors.accentText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                Column {
                  id: driftColumn
                  anchors.left: driftCursor.right
                  anchors.right: driftButtons.left
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xxs

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: {
                      var t = drift.entry.target
                      var h = Paths.home
                      return (t === h || t.indexOf(h + "/") === 0) ? "~" + t.slice(h.length) : t
                    }
                    color: slot.hasCursor ? Colors.menu.selectedText : Colors.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideMiddle
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: drift.confirming
                      ? "reset puts the repo's copy of only this file back, your edit is kept aside in dot's preserved/;"
                        + " ENTER again to reset, ESC keeps it"
                      : drift.entry.module + ", " + drift.entry.drift + ": adopt carries the edit into the repo, reset puts the repo's "
                        + "copy of this file back"
                    color: drift.confirming ? Colors.warnText : Colors.textDim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.Wrap
                  }
                }

                Row {
                  id: driftButtons
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xs

                  Repeater {
                    model: Schema.driftChoices
                    Button {
                      required property string modelData
                      variant: "chip"
                      text: modelData
                      selected: drift.choice === modelData
                      danger: modelData === "reset" && drift.confirming
                      enabled: !systemProc.running
                      onClicked: {
                        root.pane = "rows"
                        root.rowIndex = slot.index
                        root.driftChoice = Util.mapSet(root.driftChoice, drift.entry.id, modelData)
                        root.runSystem(drift.entry, modelData)
                      }
                    }
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
            color: Colors.textDim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        ListFade {
          id: rowFade
          list: rowList
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
              color: Colors.accent2Text
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
              color: Colors.warnText
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
            color: root.noticeIsError ? Colors.urgentText : Colors.okText
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }
        }
      }
    }
  }
}
