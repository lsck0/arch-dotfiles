pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// single owner: the bar, the desktop agenda and the tasks panel read this one export
Singleton {
  id: root

  // opening the panel and every mutation refresh at once
  readonly property int refreshMs: 3 * 60 * 1000
  readonly property int dueSoonMs: 15 * 60 * 1000
  // a deleted recurring task asks about its siblings; confirmation=off does not cover that prompt
  readonly property var taskArgv: ["task", "rc.verbose=nothing", "rc.confirmation=off", "rc.recurrence.confirmation=off"]
  readonly property string notifiedPath: Paths.state + "/task-due-notified.json"
  readonly property string glyph: "\u{f0756}" // md-format-list-checks

  // shared so the bar, the desktop card and ipc toggle one overlay
  property bool panelOpen: false

  // sorted rows: {uuid, desc, project, tags, due, dueMs, overdue, active, urgency}
  property var tasks: []
  property bool loaded: false
  property string errorText: ""
  readonly property int pendingCount: tasks.length
  readonly property int overdueCount: {
    var n = 0
    for (let i = 0; i < tasks.length; i++) if (tasks[i].overdue) n++
    return n
  }
  readonly property bool busy: exportProc.running || mutateProc.running

  // "uuid@due" -> ms it was announced; pruned to tasks still pending at that due
  property var notified: ({})
  property bool notifiedReady: false
  property var queue: []

  // "20260101T120000Z" -> Date, taskwarrior's basic iso
  function twDate(value) {
    var m = String(value || "").match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/)
    if (!m) return null
    return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]))
  }

  function dueText(value) {
    var d = twDate(value)
    if (!d) return ""
    var diff = d.getTime() - Date.now()
    if (diff < 0) return "overdue"
    var days = Math.floor(diff / 8.64e+07)
    if (days >= 1) return "in " + days + "d"
    var hours = Math.floor(diff / 3.6e+06)
    if (hours >= 1) return "in " + hours + "h"
    return "in " + Math.max(1, Math.floor(diff / 60000)) + "m"
  }

  // undated tasks sink below dated ones
  function buildTasks(data) {
    // a qml sequence across the var signal, not an Array, so copy by length
    var list = (data && data.length) ? Array.prototype.slice.call(data) : []
    var out = []
    for (let i = 0; i < list.length; i++) {
      let t = list[i]
      if (!t || !t.uuid) continue
      let d = t.due ? twDate(t.due) : null
      let tags = (t.tags && t.tags.length) ? Array.prototype.slice.call(t.tags).map(String) : []
      out.push({
        uuid: String(t.uuid),
        desc: String(t.description || ""),
        project: String(t.project || ""),
        tags: tags,
        dueRaw: String(t.due || ""),
        dueMs: d ? d.getTime() : Infinity,
        due: dueText(t.due),
        overdue: !!d && d.getTime() < Date.now(),
        active: !!t.start,
        urgency: Number(t.urgency) || 0
      })
    }
    out.sort(function (a, b) {
      if (a.dueMs !== b.dueMs) return a.dueMs < b.dueMs ? -1 : 1
      return b.urgency - a.urgency
    })
    return out
  }

  // a run already in flight may have read the db before a mutation landed, so ask for one more after it
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

  // queued so two quick keypresses never race
  function run(args) {
    root.queue = root.queue.concat([root.taskArgv.concat(args)])
    runNext()
  }

  function runNext() {
    if (mutateProc.running || root.queue.length === 0) return
    var next = root.queue[0]
    root.queue = root.queue.slice(1)
    mutateProc.command = next
    mutateProc.running = true
  }

  // one argv word per whitespace run, so attributes parse and nothing passes through a shell
  function add(text) {
    var words = String(text || "").trim().split(/\s+/).filter(function (w) { return w.length > 0 })
    if (words.length === 0) return
    run(["add"].concat(words))
  }

  function markDone(uuid) { if (uuid) run([uuid, "done"]) }
  function remove(uuid) { if (uuid) run([uuid, "delete"]) }
  function toggleActive(uuid, active) { if (uuid) run([uuid, active ? "stop" : "start"]) }

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
    Quickshell.execDetached(["notify-send", "-a", "quickshell-action", "-u", "low", "-h", "string:omarchy-glyph:" + root.glyph, title, body])
  }

  JsonProcess {
    id: exportProc
    command: root.taskArgv.concat(["rc.json.array=on", "status:pending", "export"])
    intervalMs: root.refreshMs
    onParsed: function (data) {
      root.tasks = root.buildTasks(data)
      root.loaded = true
      root.errorText = ""
      root.checkDue()
      root.exportDone()
    }
    onFailed: function (error) {
      root.tasks = []
      root.errorText = "task export failed"
      root.exportDone()
    }
  }

  Process {
    id: mutateProc
    stderr: StdioCollector { id: mutateErr; waitForEnd: true }
    onExited: function (exitCode) {
      root.errorText = exitCode === 0 ? "" : (String(mutateErr.text || "").trim().split("\n")[0] || "task exited " + exitCode)
      if (root.queue.length > 0) root.runNext()
      else root.refresh()
    }
  }

  FileView {
    id: notifiedFile
    path: root.notifiedPath
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        let parsed = JSON.parse(text() || "{}")
        root.notified = Util.isPlainObject(parsed) ? parsed : ({})
      } catch (e) {
        root.notified = ({})
      }
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
