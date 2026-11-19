pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  // the open panel polls; closed, the db watch below brings every change, the due texts are re-derived from the last
  // export, and a rare export catches what changes without a db write (a wait: date passing, a recurrence)
  readonly property int refreshMs: 3 * 60 * 1000
  readonly property int refreshClosedMs: 30 * 60 * 1000
  readonly property int dueSoonMs: 15 * 60 * 1000
  // d.m.y: a typed or prefilled date reads 20.11.26; ISO (with a time) and named dates parse whatever it is
  readonly property var taskArgv: ["task", "rc.verbose=nothing", "rc.confirmation=off", "rc.recurrence.confirmation=off",
    "rc.dateformat=d.m.y"]
  readonly property string notifiedPath: Paths.state + "/task-due-notified.json"
  readonly property string glyph: "\u{f0756}" // md-format-list-checks
  readonly property int msPerMinute: 60 * 1000
  readonly property int msPerHour: 60 * msPerMinute
  readonly property int msPerDay: 24 * msPerHour
  // a sync or another task process holds the db: one retry after this
  readonly property int lockRetryMs: 2000
  // a change from outside the shell (launcher capture, sync, the CLI) lands in the db file; its burst of writes is one refresh
  readonly property int dbSettleMs: 500
  readonly property string dbPath: Paths.envDir("TASKDATA", Paths.home + "/.task") + "/taskchampion.sqlite3"

  property bool panelOpen: false

  property var tasks: []
  property var exported: []
  property bool loaded: false
  // a failed change stays shown until the next change succeeds or the panel closes; an export error clears on the next export
  property string actionError: ""
  property string exportError: ""
  readonly property string errorText: actionError || exportError
  // the done, delete, start and stop changes undo can still revert, newest last: {uuid, desc, op}; lastAction is the
  // one the next undo takes
  property var undoStack: []
  readonly property int undoCountMax: 20
  readonly property var lastAction: undoStack.length > 0 ? undoStack[undoStack.length - 1] : null
  property var mutateItem: null

  // add and modify hand their text back, so the panel can put it into the input again
  signal inputFailed(string op, string uuid, string text)
  readonly property int pendingCount: tasks.length
  readonly property int overdueCount: {
    var n = 0
    for (let i = 0; i < tasks.length; i++) if (tasks[i].overdue) n++
    return n
  }

  property var notified: ({})
  property bool notifiedReady: false
  property ProcessQueue mutateQueue: ProcessQueue {
    onRunItem: function (item) { root.mutateItem = item; mutateProc.command = item.argv; mutateProc.running = true }
  }
  property var tracked: ({})

  function twDate(value) {
    var m = String(value || "").match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/)
    if (!m) return null
    return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]))
  }

  // a date as the command line takes it: the day alone at local midnight as dd.mm.yy (rc.dateformat), with a time
  // as ISO, the one form taskwarrior reads with a time beside d.m.y
  function cmdDate(value) {
    var d = twDate(value)
    if (!d) return ""
    return Qt.formatDateTime(d, d.getHours() === 0 && d.getMinutes() === 0 ? "dd.MM.yy" : "yyyy-MM-ddTHH:mm")
  }

  readonly property var editFields: ["project", "priority", "due", "scheduled", "wait", "until", "recur"]

  // The task as the command that would create it: what the edit line starts from.
  function commandText(task) {
    if (!task) return ""
    var out = [task.desc]
    for (let i = 0; i < root.editFields.length; i++) {
      let key = root.editFields[i]
      if (task.fields && task.fields[key]) out.push(key + ":" + task.fields[key])
    }
    for (let i = 0; i < task.tags.length; i++) out.push("+" + task.tags[i])
    return out.join(" ")
  }

  // The edited command against the task: only what changed, a field or tag deleted from the line cleared.
  function editArgs(task, text) {
    var list = root.words(text)
    var bare = [], set = {}, tags = {}, untag = []
    for (let i = 0; i < list.length; i++) {
      let w = list[i]
      let attr = w.match(/^([a-z]+):(.*)$/)
      if (w.length > 1 && w.charAt(0) === "+") tags[w.slice(1)] = true
      else if (w.length > 1 && w.charAt(0) === "-") untag.push(w)
      else if (attr) set[attr[1]] = w
      else bare.push(w)
    }
    var args = []
    if (bare.join(" ") !== task.desc) args = args.concat(bare)
    for (let key in set) {
      let full = root.editFields.find(function (f) { return f.indexOf(key) === 0 }) || key
      if (set[key] !== key + ":" + ((task.fields || {})[full] || "")) args.push(set[key])
    }
    for (let i = 0; i < root.editFields.length; i++) {
      let key = root.editFields[i]
      let given = Object.keys(set).some(function (k) { return key.indexOf(k) === 0 })
      if (!given && task.fields && task.fields[key]) args.push(key + ":")
    }
    for (let t in tags) if (task.tags.indexOf(t) < 0) args.push("+" + t)
    for (let i = 0; i < task.tags.length; i++) if (!tags[task.tags[i]]) args.push("-" + task.tags[i])
    return args.concat(untag)
  }

  function dueText(value) {
    var d = twDate(value)
    if (!d) return ""
    var diff = d.getTime() - Date.now()
    if (diff < 0) return "overdue"
    var days = Math.floor(diff / root.msPerDay)
    if (days >= 1) return "in " + days + "d"
    var hours = Math.floor(diff / root.msPerHour)
    if (hours >= 1) return "in " + hours + "h"
    return "in " + Math.max(1, Math.floor(diff / root.msPerMinute)) + "m"
  }

  // when a not-yet-ready task is scheduled: the time today, the weekday this week, else the date; empty once ready
  // until: the date the task expires and is deleted, shown as "until <day>"
  function untilText(value) {
    var d = twDate(value)
    if (!d) return ""
    var now = new Date()
    if (d.toDateString() === now.toDateString()) return "until " + Qt.formatDateTime(d, "HH:mm")
    return "until " + (d.getTime() - now.getTime() < 6 * root.msPerDay ? Qt.formatDateTime(d, "ddd") : Qt.formatDateTime(d, "MMM d"))
  }

  function scheduledText(value) {
    var d = twDate(value)
    if (!d || d.getTime() <= Date.now()) return ""
    var now = new Date()
    var timed = d.getHours() !== 0 || d.getMinutes() !== 0
    if (d.toDateString() === now.toDateString()) return "@" + Qt.formatDateTime(d, "HH:mm")
    var day = d.getTime() - now.getTime() < 6 * root.msPerDay ? Qt.formatDateTime(d, "ddd") : Qt.formatDateTime(d, "MMM d")
    return "@" + day + (timed ? " " + Qt.formatDateTime(d, "HH:mm") : "")
  }

  // timew exports tags sorted: every tag counts, the description is the join key back to a task. `:day` returns every
  // interval touching today whole, so each counts from midnight on: one left open for days is not days of work today
  function buildTracked(data) {
    var list = (data && data.length) ? Array.prototype.slice.call(data) : []
    var byTag = {}
    var closed = 0
    var openMs = 0
    var dayStartMs = new Date().setHours(0, 0, 0, 0)
    for (let i = 0; i < list.length; i++) {
      let iv = list[i]
      let start = twDate(iv.start)
      if (!start) continue
      let startMs = Math.max(start.getTime(), dayStartMs)
      if (!iv.end) { openMs = startMs; continue }
      let end = twDate(iv.end)
      if (!end) continue
      let secs = Math.max(0, (end.getTime() - startMs) / 1000)
      closed += secs
      let tags = iv.tags || []
      for (let j = 0; j < tags.length; j++) byTag[tags[j]] = (byTag[tags[j]] || 0) + secs
    }
    root.openTags = list.length > 0 && !list[list.length - 1].end ? Array.prototype.slice.call(list[list.length - 1].tags || []) : []
    root.openStartMs = openMs
    root.closedSeconds = closed
    return byTag
  }

  property var openTags: []
  property real openStartMs: 0
  property real closedSeconds: 0

  function openSeconds() {
    return root.openStartMs > 0 ? Math.max(0, (root.nowTick - root.openStartMs) / 1000) : 0
  }

  function trackedText(desc) {
    var open = root.openTags.indexOf(desc) >= 0 ? root.openSeconds() : 0
    return root.durationText((root.tracked[desc] || 0) + open)
  }

  function durationText(secs) {
    if (secs < 60) return ""
    var h = Math.floor(secs / 3600)
    var m = Math.floor((secs % 3600) / 60)
    return (h > 0 ? h + "h" : "") + m + "m"
  }

  property real nowTick: Date.now()
  // the clock behind the elapsed and tracked texts: only the panel and a running task (the agenda's row) show one
  Timer {
    interval: 30000
    running: root.panelOpen || root.activeTask !== null
    repeat: true
    triggeredOnStart: true
    onTriggered: root.nowTick = Date.now()
  }

  readonly property var activeTask: {
    for (let i = 0; i < root.tasks.length; i++) if (root.tasks[i].active) return root.tasks[i]
    return null
  }

  function activeElapsedText() {
    var t = root.activeTask
    if (!t || !t.startMs) return ""
    return root.durationText(Math.max(0, (root.nowTick - t.startMs) / 1000))
  }

  readonly property int trackedTotalSeconds: root.closedSeconds + root.openSeconds()

  function totalTrackedText() {
    return root.durationText(root.trackedTotalSeconds)
  }

  function buildTasks(data) {
    var list = (data && data.length) ? Array.prototype.slice.call(data) : []
    var out = []
    for (let i = 0; i < list.length; i++) {
      let t = list[i]
      if (!t || !t.uuid) continue
      let d = t.due ? twDate(t.due) : null
      let s = t.start ? twDate(t.start) : null
      let tags = (t.tags && t.tags.length) ? Array.prototype.slice.call(t.tags).map(String) : []
      out.push({
        uuid: String(t.uuid),
        desc: String(t.description || ""),
        project: String(t.project || ""),
        priority: String(t.priority || ""),
        tags: tags,
        dueRaw: String(t.due || ""),
        dueMs: d ? d.getTime() : Infinity,
        due: dueText(t.due),
        scheduled: scheduledText(t.scheduled),
        until: untilText(t.until),
        // the raw values the edit line writes back as a command: dates as taskwarrior's yyyy-mm-ddThh:mm in local time
        fields: {
          project: String(t.project || ""), priority: String(t.priority || ""), due: cmdDate(t.due),
          scheduled: cmdDate(t.scheduled), wait: cmdDate(t.wait), until: cmdDate(t.until), recur: String(t.recur || "")
        },
        recur: String(t.recur || ""),
        blocked: !!(t.depends && t.depends.length),
        overdue: !!d && d.getTime() < Date.now(),
        active: !!t.start,
        startMs: s ? s.getTime() : 0,
        urgency: Number(t.urgency) || 0
      })
    }
    // overdue first, then urgency: it already weighs due proximity, priority and the tag coefficients, like task next
    out.sort(function (a, b) {
      if (a.overdue !== b.overdue) return a.overdue ? -1 : 1
      return b.urgency - a.urgency
    })
    return out
  }

  property bool exportAgain: false

  function refresh() {
    if (exportProc.running) root.exportAgain = true
    else exportProc.run()
  }

  function exportDone() {
    if (!root.exportAgain) return
    root.exportAgain = false
    exportProc.run()
  }

  // item: {op, uuid, desc, text}; op is the task verb, except "undo"
  function run(args, item) {
    root.mutateQueue.enqueue(Object.assign({ op: "", uuid: "", desc: "", text: "", retried: false }, item || {},
      { argv: root.taskArgv.concat(args) }))
  }

  function words(text) {
    return String(text || "").trim().split(/\s+/).filter(function (w) { return w.length > 0 })
  }

  function add(text) {
    var list = root.withRecurDue(root.words(text), false)
    if (list.length === 0) return
    run(["add"].concat(list), { op: "add", text: text })
  }

  // taskwarrior refuses recur: without a due date, the anchor each instance is scheduled from: the end of today when none is given (today is its midnight, overdue at once)
  function withRecurDue(list, hasDue) {
    var recurs = list.some(function (w) { return /^recur:\S/.test(w) })
    var due = list.some(function (w) { return /^due:\S/.test(w) })
    return recurs && !due && !hasDue ? list.concat(["due:eod"]) : list
  }

  // the edit line holds the whole task as a command (commandText): what changed is set, what was deleted is cleared
  function modify(task, text) {
    if (!task || root.words(text).length === 0) return
    var list = root.editArgs(task, text)
    if (list.length === 0) return
    list = root.withRecurDue(list, task.dueRaw !== "" && list.indexOf("due:") < 0)
    run([task.uuid, "modify"].concat(list), { op: "modify", uuid: task.uuid, desc: task.desc, text: text })
  }

  function runVerb(task, op) { run([task.uuid, op], { op: op, uuid: task.uuid, desc: task.desc }) }

  // One task tracks at a time: timew start closes the running interval, so the task that owned it stops too.
  function stopOthers(uuid) {
    for (let i = 0; i < root.tasks.length; i++) if (root.tasks[i].active && root.tasks[i].uuid !== uuid) run([root.tasks[i].uuid, "stop"])
  }

  function markDone(task) { if (task) runVerb(task, "done") }
  function remove(task) { if (task) runVerb(task, "delete") }
  function toggleActive(task) {
    if (!task) return
    if (!task.active) root.stopOthers(task.uuid)
    runVerb(task, task.active ? "stop" : "start")
  }

  // done and delete go back to pending by uuid, which a sync in between does not break, unlike task undo
  function undoLast() {
    var last = root.lastAction
    if (!last) return
    root.undoStack = root.undoStack.slice(0, -1)
    if (last.op === "stop") root.stopOthers(last.uuid)
    var args = last.op === "start" ? [last.uuid, "stop"]
      : last.op === "stop" ? [last.uuid, "start"]
      : [last.uuid, "modify", "status:pending"]
    run(args, { op: "undo", uuid: last.uuid, desc: last.desc, undone: last })
  }

  function mutateFinish(item, exitCode, stderr) {
    if (exitCode !== 0) {
      root.actionError = String(stderr || "").trim().split("\n")[0] || "task exited " + exitCode
      if (item.op === "add" || item.op === "modify") root.inputFailed(item.op, item.uuid, item.text)
      if (item.op === "undo") root.undoStack = root.undoStack.concat([item.undone]).slice(-root.undoCountMax)
      return
    }
    root.actionError = ""
    if (["done", "delete", "start", "stop"].indexOf(item.op) >= 0)
      root.undoStack = root.undoStack.concat([{ uuid: item.uuid, desc: item.desc, op: item.op }]).slice(-root.undoCountMax)
  }

  onPanelOpenChanged: if (!panelOpen) root.actionError = ""

  function checkDue() {
    if (!root.notifiedReady || !root.loaded) return
    var now = Date.now()
    var next = ({})
    var fresh = []
    for (let i = 0; i < root.tasks.length; i++) {
      let t = root.tasks[i]
      if (t.dueMs === Infinity) continue
      let key = t.uuid + "@" + t.dueRaw
      if (root.notified[key]) { next[key] = root.notified[key]; continue }
      if (t.dueMs - now > root.dueSoonMs) continue
      next[key] = now
      fresh.push(t)
    }
    var changed = fresh.length > 0 || Object.keys(next).length !== Object.keys(root.notified).length
    root.notified = next
    if (changed) notifiedFile.setText(JSON.stringify(next) + "\n")
    if (fresh.length === 0) return
    var title = fresh.length === 1 ? (fresh[0].overdue ? "Task overdue" : "Task due " + fresh[0].due) : fresh.length + " tasks due"
    var body = fresh.map(function (t) { return fresh.length === 1 ? t.desc : t.desc + " (" + t.due + ")" }).join("\n")
    Quickshell.execDetached(["notify-send", "-a", "quickshell-action", "-u", "low", "-h", "string:lsck0-glyph:" + root.glyph, "--", title, body])
  }

  JsonProcess {
    id: exportProc
    command: root.taskArgv.concat(["rc.json.array=on", "status:pending", "export"])
    intervalMs: root.panelOpen ? root.refreshMs : root.refreshClosedMs
    onParsed: function (data) {
      root.exported = data
      root.tasks = root.buildTasks(data)
      root.loaded = true
      root.exportError = ""
      root.checkDue()
      root.exportDone()
    }
    onFailed: function (error) {
      // keep the last-good list: a transient export failure (a db lock from an overlapping poll) must not blank the widget
      root.loaded = true
      root.exportError = "task export failed"
      root.exportDone()
    }
  }

  JsonProcess {
    id: timewProc
    command: ["timew", "export", ":day"]
    // tracked time shows in the panel only
    intervalMs: root.panelOpen ? root.refreshMs : 0
    onParsed: function (data) { root.tracked = root.buildTracked(data) }
  }

  Process {
    id: mutateProc
    stderr: StdioCollector { id: mutateErr; waitForEnd: true }
    onExited: function (exitCode) {
      var item = root.mutateItem
      if (exitCode !== 0 && !item.retried && /database is locked/.test(String(mutateErr.text || ""))) {
        item.retried = true
        lockRetry.start()
        return
      }
      root.mutateFinish(item, exitCode, mutateErr.text)
      timewProc.refresh()
      root.mutateQueue.done()
      if (!root.mutateQueue.running) root.refresh()
    }
  }

  Timer {
    interval: root.refreshMs
    running: !root.panelOpen && root.loaded
    repeat: true
    onTriggered: {
      root.tasks = root.buildTasks(root.exported)
      root.checkDue()
    }
  }

  Timer {
    id: lockRetry
    interval: root.lockRetryMs
    onTriggered: mutateProc.running = true
  }

  // watched, never read: the db is binary, only its change matters
  FileView {
    path: root.dbPath
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: {
      dbSettle.restart()
      Util.rearmWatch(this)
    }
  }

  Timer {
    id: dbSettle
    interval: root.dbSettleMs
    onTriggered: root.refresh()
  }

  FileView {
    id: notifiedFile
    path: root.notifiedPath
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.notified = Util.parseObject(text())
      root.notifiedReady = true
      root.checkDue()
    }
    onLoadFailed: {
      root.notified = ({})
      root.notifiedReady = true
      root.checkDue()
    }
  }
}
