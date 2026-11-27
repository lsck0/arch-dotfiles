pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../../services"
import "../../services/AppSearch.js" as AppSearch
import "../reminders/ReminderFlowModel.js" as ReminderFlowModel

Item {
  id: root

  property AppLibrary appLibrary: null
  property bool opened: false
  property string filterText: ""
  // the mode prefix openWith started on: ESC clears back to it, then closes
  property string homeText: ""
  property int selectedIndex: 0
  property var rows: []

  readonly property int rowHeight: Style.space(44)
  readonly property int iconSize: Style.space(28)
  // icon files that failed to load once (an Icon= path the package does not ship): their rows keep the glyph
  property var brokenIcons: ({})

  readonly property var prefixes: ({ "=": "calc", ">": "run", "@": "windows", "?": "keys", "+": "task", "!": "remind", "#": "note" })
  readonly property string mode: prefixes[filterText.charAt(0)] || "apps"
  readonly property string modeQuery: mode === "apps" ? filterText : filterText.substring(1).trim()

  readonly property var modeTitles: ({ apps: "applications", calc: "calculator", run: "run", windows: "windows", keys: "keybinds", task: "new task", remind: "reminder", note: "note" })
  readonly property var modePlaceholders: ({ apps: "search applications", calc: "enter an expression", run: "command to run", windows: "search windows", keys: "search keybinds", task: "Dino letter project:dino due:fri +uni", remind: "10m tea, 15:00 dentist", note: "a thought for ~/sync/notes/inbox.md" })
  readonly property var modeHints: ({
    apps: [["ENTER", "open"], ["=", "calc"], [">", "run"], ["@", "windows"], [":", "clipboard"], ["?", "keys"], ["+ ! #", "capture"]],
    task: [["ENTER", "add"]],
    remind: [["ENTER", "set"], ["DEL", "cancel pending"]],
    note: [["ENTER", "save"]],
    calc: [["ENTER", "copy"]],
    run: [["ENTER", "run"], ["SHIFT+ENTER", "in terminal"]],
    windows: [["^/v", "select"], ["ENTER", "focus"]],
    keys: [["^/v", "select"], ["ENTER", "close"]]
  })
  // ESC clears back to the home prefix, then closes
  readonly property bool escClears: filterText !== "" && filterText.trim() !== homeText.trim()
  // what an empty list says while nothing is typed
  readonly property var modeEmpty: ({ apps: "> NO APPS", calc: "> TYPE AN EXPRESSION", run: "> TYPE A COMMAND", windows: "> NO WINDOWS", keys: "> NO KEYBINDS", task: "> TYPE A TASK", remind: "> 10M|15:00 \u00b7 NAME", note: "> TYPE A NOTE" })

  readonly property var modifierBits: [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"]]
  // hyprctl names that the hint grammar spells differently; every other key name is shown upper case
  readonly property var keyNames: ({ "mouse:272": "LMB", "mouse:273": "RMB", "mouse:274": "MMB", "Return": "ENTER",
                                     "Escape": "ESC", "Delete": "DEL" })
  // binds on a keycode are a position on the board, whatever the layout prints there
  readonly property var keycodeNames: ({ 49: "BELOW ESC" })
  readonly property string keysSeparator: " / "
  property var binds: []
  property string bindsState: ""

  readonly property int calcDebounceMs: 150
  property string calcResult: ""
  property string calcState: ""
  // ENTER while qalc still runs: copy the result once it lands
  property bool copyWhenReady: false
  readonly property int exitNotFound: 127
  readonly property int calcTimeoutS: 5

  // > run commands, newest first; shown when the run query is empty
  property var runHistory: []
  readonly property int runHistoryMax: 20
  readonly property string terminal: "kitty"

  function open() {
    panel.screen = Util.focusedScreen()
    root.opened = true
    root.filterText = ""
    root.homeText = ""
    root.selectedIndex = 0
    // focusHistoryID for the @ order; lands before a typed @ is read
    Hyprland.refreshToplevels()
    root.rebuild()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.copyWhenReady = false
    calcDebounce.stop()
    calcProc.running = false
    bindsProc.running = false
  }

  function toggle() { root.opened ? root.close() : root.open() }

  function appRows() {
    if (!root.appLibrary) return []
    var entries = root.appLibrary.sortedEntries(root.modeQuery)
    var out = []
    for (let i = 0; i < entries.length; i++) {
      const e = entries[i]
      const name = AppSearch.entryName(e)
      const sub = AppSearch.entrySubtext(e)
      const icon = root.appLibrary.iconSource(e.icon)
      out.push(root.row("app", "\u{f08c6}", name, sub.toLowerCase() === name.toLowerCase() ? "" : sub, e, root.brokenIcons[icon] ? "" : icon))
    }
    return out
  }

  // icon: an icon file shown instead of the glyph, apps and windows only; keys: the keybind rows' hint
  function row(kind, glyph, name, sub, payload, icon, keys) {
    return { kind: kind, name: name, sub: sub, icon: icon || "", glyph: glyph, keys: keys || "", payload: payload }
  }

  // the query's words, each of which a window or keybind row must contain
  function queryWords() { return root.modeQuery.toLowerCase().split(/\s+/).filter(function(w) { return w.length > 0 }) }

  function matchesAll(words, haystack) {
    return words.every(function(w) { return haystack.indexOf(w) >= 0 })
  }

  function focusOrder(toplevel) {
    const id = (toplevel.lastIpcObject || {}).focusHistoryID
    return typeof id === "number" && id >= 0 ? id : Number.MAX_SAFE_INTEGER
  }

  // most recently focused first, every word matched like apps and keys
  function windowRows() {
    var words = root.queryWords()
    var values = Array.from(Hyprland.toplevels.values)
    values.sort(function(a, b) { return root.focusOrder(a) - root.focusOrder(b) })
    var out = []
    for (let i = 0; i < values.length; i++) {
      const t = values[i]
      // quickshell never prunes a toplevel whose closewindow it missed; closed or unmapped ones lack these
      if (!t.wayland || !t.workspace) continue
      const cls = String(t.wayland.appId || "")
      const title = String(t.title || "")
      const ws = String(t.workspace.id)
      if (!root.matchesAll(words, (title + " " + cls + " " + ws).toLowerCase())) continue
      out.push(root.row("window", "\u{f2d0}", title || cls || "--", "[" + ws + "] " + cls, String(t.address || ""),
                        cls ? Util.iconSource(cls.toLowerCase()) : ""))
    }
    return out
  }

  function calcRows() {
    if (!root.modeQuery) return []
    var text = root.calcState === "missing" ? "x ERR qalc is not installed"
      : root.calcState === "error" ? "x ERR"
      : root.calcState === "loading" && !root.calcResult ? "--"
      : root.calcResult
    return [root.row("calc", "\u{f00ec}", "= " + text, root.modeQuery, root.calcResult)]
  }

  function runRows() {
    var q = root.modeQuery
    var out = q ? [root.row("run", "\u{f018d}", q, "sh -c", q)] : []
    for (let i = 0; i < root.runHistory.length; i++) {
      const cmd = root.runHistory[i]
      if (cmd === q || cmd.indexOf(q) < 0) continue
      out.push(root.row("run", "\u{f02da}", cmd, "recent", cmd))
    }
    return out
  }

  function runRecord(cmd) {
    var next = [cmd].concat(root.runHistory.filter(function(c) { return c !== cmd })).slice(0, root.runHistoryMax)
    root.runHistory = next
    runHistoryFile.setText(JSON.stringify(next) + "\n")
  }

  // what taskwarrior will take from the words: project, tags, priority and dates
  function taskPreview(words) {
    var parts = []
    for (let i = 0; i < words.length; i++) {
      const w = words[i]
      const project = w.match(/^pro(?:ject)?:(.+)$/)
      if (project) parts.push(project[1])
      else if (/^(?:prio(?:rity)?|due|sch(?:eduled)?|wait|recur):./.test(w) || /^\+\S/.test(w)) parts.push(w)
    }
    return parts.length > 0 ? parts.join(", ") : "task add"
  }

  // the duration grammar and the clock time are ReminderFlowModel's, so the overlay and capture.nu read the same words
  function reminderPreviewRows(words, script) {
    if (words.length === 0) return []
    const now = new Date()
    const clock = ReminderFlowModel.clockNext(words[0], now)
    const minutes = ReminderFlowModel.minutesOf(words[0])
    if (!clock && minutes <= 0)
      return [root.row("capture", "\u{f0f3}", "x " + ReminderFlowModel.WHEN_HINT, "reminder", null)]
    const at = clock || new Date(now.getTime() + minutes * 60000)
    const name = words.slice(1).join(" ") || (clock ? "reminder at " + Qt.formatDateTime(at, Util.timeFormat) : minutes + "-min reminder")
    const sub = "at " + Qt.formatDateTime(at, Util.timeFormat) + (clock ? " (in " + TimerState.remainingText((at.getTime() - now.getTime()) / 1000) + ")" : "")
    return [root.row("capture", "\u{f0f3}", name, sub, [script, "remind"].concat(words))]
  }

  // what is already set, so a duplicate is seen and cancelled (DEL) without the overlay
  function reminderPendingRows() {
    return TimerState.reminders.map(function(r) { return root.row("reminder", "\u{f009c}", r.label, "pending, at " + r.atTime, r.unit) })
  }

  function reminderCancelAt(index) {
    const row = root.rows[index]
    if (row && row.kind === "reminder") Quickshell.execDetached([Paths.script("reminder.nu"), "cancel", row.payload])
  }

  // capture.nu takes the words as separate arguments, so taskwarrior's own attribute syntax goes through unchanged
  function captureRows() {
    var words = root.modeQuery.split(/\s+/).filter(function (w) { return w !== "" })
    var script = Paths.script("capture.nu")
    if (root.mode === "remind") return reminderPreviewRows(words, script).concat(reminderPendingRows())
    if (words.length === 0) return []
    if (root.mode === "task")
      return [root.row("capture", "\u{f0ae}", root.modeQuery, root.taskPreview(words), [script, "task"].concat(words))]
    return [root.row("capture", "\u{f0f6}", root.modeQuery, "~/sync/notes/inbox.md", [script, "note"].concat(words))]
  }

  function bindKeys(bind) {
    var parts = []
    for (let i = 0; i < root.modifierBits.length; i++) {
      if (bind.modmask & root.modifierBits[i][0]) parts.push(root.modifierBits[i][1])
    }
    const key = String(bind.key || "")
    parts.push(bind.catch_all ? "ANY"
      : root.keyNames[key] || key.toUpperCase() || root.keycodeNames[bind.keycode] || "CODE:" + bind.keycode)
    return parts.join("+")
  }

  // one row per action: binds sharing a description and a submap (h and Left, a letter with and without SUPER) fold
  function bindRows() {
    var words = root.queryWords()
    var topLevel = []
    var submaps = []
    var rowOf = ({})
    for (let i = 0; i < root.binds.length; i++) {
      const b = root.binds[i]
      const keys = root.bindKeys(b)
      const name = String(b.description || "") || String(b.dispatcher || "") + " " + String(b.arg || "")
      const sub = b.submap ? "[" + b.submap + "]" : ""
      const id = sub + "\n" + name
      if (rowOf[id]) {
        rowOf[id].keys += root.keysSeparator + keys
        continue
      }
      rowOf[id] = root.row("bind", "\u{f030c}", name, sub, "", "", keys)
      if (b.submap) submaps.push(rowOf[id])
      else topLevel.push(rowOf[id])
    }
    return topLevel.concat(submaps).filter(function(row) {
      return root.matchesAll(words, (row.name + " " + row.keys + " " + row.sub).toLowerCase())
    })
  }

  function rebuild() {
    root.rows = root.mode === "calc" ? calcRows()
      : root.mode === "run" ? runRows()
      : root.mode === "windows" ? windowRows()
      : root.mode === "keys" ? bindRows()
      : (root.mode === "task" || root.mode === "remind" || root.mode === "note") ? captureRows()
      : appRows()
    root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.rows.length - 1))
  }

  function setFilter(text) {
    if (text === ":") {
      root.close()
      Quickshell.execDetached(Paths.ipcCall("clipboard", "open"))
      return
    }
    const wasKeys = root.mode === "keys"
    root.copyWhenReady = false
    root.filterText = text
    root.selectedIndex = 0
    if (root.mode === "keys" && !wasKeys) {
      root.binds = []
      root.bindsState = "loading"
      bindsProc.running = true
    }
    if (root.mode === "calc") {
      root.calcState = root.modeQuery ? "loading" : ""
      if (root.modeQuery) calcDebounce.restart()
      else calcDebounce.stop()
    }
    root.rebuild()
    // with nothing typed, ENTER goes back to the previously focused window, like alt-tab
    if (root.mode === "windows" && !root.modeQuery && root.rows.length > 1) root.selectedIndex = 1
  }

  // one line, so a pasted multi-line selection stays one capture or command
  function paste() {
    const text = String(Quickshell.clipboardText || "").replace(/\s*\n\s*/g, " ")
    // ":" alone opens the clipboard plugin, never by a paste
    if (!text || root.filterText + text === ":") return
    root.setFilter(root.filterText + text)
  }

  function selectAt(index) {
    pointerGate.reset()
    root.selectedIndex = Math.max(0, Math.min(index, root.rows.length - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  // inTerminal: SHIFT+ENTER, a > run command in a terminal window instead of in the background
  function activateAt(index, inTerminal) {
    if (index < 0 || index >= root.rows.length) return
    var row = root.rows[index]
    // a pending reminder only takes DEL; ENTER on it must not close the launcher on nothing
    if (row.kind === "reminder") return
    if (row.kind === "app") {
      if (!root.appLibrary) return
      root.appLibrary.launch(row.payload.id, row.name)
    } else if (row.kind === "window") {
      if (!row.payload) return
      const address = row.payload.indexOf("0x") === 0 ? row.payload : "0x" + row.payload
      Hyprland.dispatch("hl.dsp.focus({ window = 'address:" + address + "' })")
    } else if (row.kind === "calc") {
      if (root.calcState === "loading") root.copyWhenReady = true
      if (root.calcState !== "" || !row.payload) return
      Quickshell.execDetached(["wl-copy", "--", row.payload])
    } else if (row.kind === "run") {
      root.runRecord(row.payload)
      Quickshell.execDetached(inTerminal ? ["uwsm-app", "--", root.terminal, "-e", "sh", "-c", "--", row.payload]
        : ["uwsm-app", "--", Paths.script("run.nu"), row.payload])
    } else if (row.kind === "capture") {
      if (!row.payload) return
      // capture.nu reopens the launcher on the typed line when taskwarrior rejects it
      Quickshell.execDetached({ command: row.payload, environment: { CAPTURE_FROM_LAUNCHER: "1" } })
    }
    root.close()
  }

  Timer {
    id: calcDebounce
    interval: root.calcDebounceMs
    onTriggered: {
      calcProc.running = false
      // unicode off: a copied minus or exponent pastes as ASCII; command[4] stays the query calcProc checks against
      calcProc.command = ["sh", "-c", "command -v qalc >/dev/null 2>&1 || exit " + root.exitNotFound + "; exec timeout " + root.calcTimeoutS
                          + " qalc -t -s 'unicode off' \" $1\"", "qalc", root.modeQuery]
      calcProc.running = true
    }
  }

  Process {
    id: calcProc
    stdout: StdioCollector { id: calcOut; waitForEnd: true }
    onExited: function(code) {
      if (root.mode !== "calc" || calcProc.command[4] !== root.modeQuery) return
      var text = String(calcOut.text || "").trim().split("\n").pop()
      root.calcState = code === root.exitNotFound ? "missing" : code !== 0 || !text ? "error" : ""
      root.calcResult = root.calcState === "" ? text : ""
      root.rebuild()
      if (root.copyWhenReady) {
        root.copyWhenReady = false
        root.activateAt(0)
      }
    }
  }

  Process {
    id: bindsProc
    command: ["hyprctl", "binds", "-j"]
    stdout: StdioCollector { id: bindsOut; waitForEnd: true }
    onExited: function(code) {
      var binds = null
      try { if (code === 0) binds = JSON.parse(bindsOut.text) } catch (e) {}
      root.binds = Array.isArray(binds) ? binds : []
      root.bindsState = Array.isArray(binds) ? "" : "error"
      if (root.mode === "keys") root.rebuild()
    }
  }

  FileView {
    id: runHistoryFile
    path: Paths.state + "/launcher-run.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        const list = JSON.parse(text())
        root.runHistory = Array.isArray(list) ? list.filter(function(c) { return typeof c === "string" && c }) : []
      } catch (e) {
        root.runHistory = []
      }
      if (root.opened && root.mode === "run") root.rebuild()
    }
    onLoadFailed: root.runHistory = []
  }

  Connections {
    target: TimerState
    enabled: root.opened && root.mode === "remind"
    function onReminderListChanged() { root.rebuild() }
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { if (root.opened && root.mode === "apps") root.rebuild() }
  }

  Connections {
    target: Hyprland.toplevels
    enabled: root.opened && root.mode === "windows"
    function onValuesChanged() { root.rebuild() }
  }

  IpcHandler {
    target: "appsearch"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.open(); return "ok" }
    // opens on a mode: "+ " for a task, "! " for a reminder, "# " for a note
    function openWith(text: string): string {
      root.open()
      root.setFilter(text)
      root.homeText = root.mode === "apps" ? "" : text.charAt(0) + " "
      return "ok"
    }
    function close(): string { root.close(); return "ok" }
  }

  OverlayCard {
    id: panel
    open: root.opened
    name: "appsearch"
    title: root.modeTitles[root.mode]
    suffix: "[" + String(root.rows.length) + "]"
    prompt: true
    // a bare prefix leaves the line to the mode's placeholder, the one place the capture grammar is shown
    query: root.mode === "apps" || root.modeQuery ? root.filterText : ""
    placeholder: (root.mode === "apps" ? "" : root.filterText.charAt(0) + " ") + root.modePlaceholders[root.mode]
    hints: root.modeHints[root.mode].concat([["ESC", root.escClears ? "clear" : "close"]])
    onDismissed: root.close()

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Delete && root.mode === "remind") root.reminderCancelAt(root.selectedIndex)
        else if ((event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier))
                 || (event.key === Qt.Key_Insert && (event.modifiers & Qt.ShiftModifier))) root.paste()
        else {
          event.accepted = listKeys.handle(event)
          return
        }
        event.accepted = true
      }
    }

    FilterListKeys {
      id: listKeys
      cursor: listCursor
      index: root.selectedIndex
      filter: root.filterText
      onEscaped: root.escClears ? root.setFilter(root.homeText) : root.close()
      onStepped: function (delta) { root.selectAt(listCursor.step(root.selectedIndex, delta)) }
      onJumped: function (index) { root.selectAt(index) }
      onActivated: function (modifiers) { root.activateAt(root.selectedIndex, (modifiers & Qt.ShiftModifier) !== 0) }
      onFilterCleared: root.setFilter(root.homeText)
      onFilterEdited: function (text) { root.setFilter(text) }
    }

    ListCursor {
      id: listCursor
      list: resultList
      rowHeight: root.rowHeight
    }

    PointerMoveGate {
      id: pointerGate
      referenceItem: panel.card
    }

    FadedList {
      id: resultList
      readonly property int rowPitch: root.rowHeight + spacing
      readonly property int pageRows: Math.max(1, Math.floor((parent.height + spacing) / rowPitch))
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.rightMargin: resultBar.gutter
      height: pageRows * rowPitch - spacing
      clip: true
      model: root.rows
      spacing: Style.spacing.xxs
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ListScrollBar { id: resultBar; list: resultList }
      fade: resultFade

      delegate: CursorFill {
        id: rowDelegate
        required property var modelData
        required property int index
        readonly property bool selected: index === root.selectedIndex

        hasCursor: selected
        hovered: rowMouse.containsMouse
        width: ListView.view.width
        height: root.rowHeight
        opacity: panel.boot.rowOpacity(index)

        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.spacing.md
          anchors.rightMargin: Style.spacing.md
          spacing: Style.spacing.md

          Label {
            id: cursorMark
            anchors.verticalCenter: parent.verticalCenter
            width: Style.spacing.md
            text: rowDelegate.selected ? ">" : ""
            color: Colors.accentText
            horizontalAlignment: Text.AlignHCenter
            layer.enabled: rowDelegate.selected && Style.fx.glow > 0
            layer.effect: Glow {}
          }

          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: root.iconSize
            height: root.iconSize

            Image {
              id: rowIcon
              anchors.fill: parent
              visible: source !== "" && status === Image.Ready
              sourceSize.width: Math.round(root.iconSize * Screen.devicePixelRatio)
              sourceSize.height: Math.round(root.iconSize * Screen.devicePixelRatio)
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              source: rowDelegate.modelData.icon
              onStatusChanged: if (status === Image.Error) root.brokenIcons[rowDelegate.modelData.icon] = true
            }

            Label {
              anchors.centerIn: parent
              visible: !rowIcon.visible
              text: rowDelegate.modelData.glyph
              color: rowDelegate.selected ? Colors.menu.selectedText : Colors.menu.text
              icon: true
              font.pixelSize: Style.font.heading
            }
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - root.iconSize - cursorMark.width - keysLabel.width - parent.spacing * 3

            Label {
              width: parent.width
              textFormat: Text.StyledText
              text: rowDelegate.modelData.kind === "app"
                ? AppSearch.highlight(rowDelegate.modelData.name, root.modeQuery,
                    String(rowDelegate.selected ? Colors.textOnFill(Colors.accent2Text, Colors.menu.selectedBackground) : Colors.accent2Text))
                : AppSearch.escapeHtml(rowDelegate.modelData.name)
              color: rowDelegate.selected ? Colors.menu.selectedText : Colors.menu.text
              elide: Text.ElideRight
            }

            Label {
              width: parent.width
              visible: text.length > 0
              text: rowDelegate.modelData.sub
              color: rowDelegate.selected ? Colors.menu.selectedText : Colors.textDim
              caption: true
              elide: Text.ElideRight
            }
          }

          Label {
            id: keysLabel
            anchors.verticalCenter: parent.verticalCenter
            width: text ? implicitWidth : 0
            text: rowDelegate.modelData.keys
            color: rowDelegate.selected ? Colors.menu.selectedText : Colors.accentText
            caption: true
            font.bold: true
          }
        }

        HudFrame { shown: rowDelegate.selected }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPositionChanged: function(mouse) {
            if (pointerGate.moved(rowDelegate, mouse)) root.selectedIndex = rowDelegate.index
          }
          onClicked: root.activateAt(rowDelegate.index)
        }
      }

      EmptyState {
        shown: root.rows.length === 0
        glyph: "\u{f003b}"
        text: root.mode === "keys" && root.bindsState === "loading" ? "> LOADING"
          : root.mode === "keys" && root.bindsState === "error" ? "> HYPRCTL BINDS FAILED"
          : root.modeQuery ? "> NO MATCH" : root.modeEmpty[root.mode]
      }
    }

    ListFade {
      id: resultFade
      list: resultList
    }
  }
}
