pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  readonly property int refreshMs: 3 * 60 * 1000
  readonly property int dueSoonMs: 15 * 60 * 1000
  readonly property var taskArgv: ["task", "rc.verbose=nothing", "rc.confirmation=off", "rc.recurrence.confirmation=off"]
  readonly property string notifiedPath: Paths.state + "/task-due-notified.json"
  readonly property string glyph: "\u{f0756}" // md-format-list-checks

  property bool panelOpen: false

  property var tasks: []
  property bool loaded: false
  property string errorText: ""
  readonly property int pendingCount: tasks.length
  readonly property int overdueCount: {
    var n = 0
    for (let i = 0; i < tasks.length; i++) if (tasks[i].overdue) n++
    return n
  }

  property var notified: ({})
  property bool notifiedReady: false
  property ProcessQueue mutateQueue: ProcessQueue {
    onRunItem: function (item) { mutateProc.command = item; mutateProc.running = true }
  }
  property var tracked: ({})

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

  // timew exports tags sorted: every tag counts, the description is the join key back to a task
  function buildTracked(data) {
    var list = (data && data.length) ? Array.prototype.slice.call(data) : []
    var byTag = {}
    var closed = 0
    var openMs = 0
    for (let i = 0; i < list.length; i++) {
      let iv = list[i]
      let start = twDate(iv.start)
      if (!start) continue
      if (!iv.end) { openMs = start.getTime(); continue }
      let end = twDate(iv.end)
      if (!end) continue
      let secs = Math.max(0, (end.getTime() - start.getTime()) / 1000)
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
  Timer { interval: 30000; running: true; repeat: true; onTriggered: root.nowTick = Date.now() }

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
        overdue: !!d && d.getTime() < Date.now(),
        active: !!t.start,
        startMs: s ? s.getTime() : 0,
        urgency: Number(t.urgency) || 0
      })
    }
    out.sort(function (a, b) {
      if (a.dueMs !== b.dueMs) return a.dueMs < b.dueMs ? -1 : 1
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

  function run(args) {
    root.mutateQueue.enqueue(root.taskArgv.concat(args))
  }

  function add(text) {
    var words = String(text || "").trim().split(/\s+/).filter(function (w) { return w.length > 0 })
    if (words.length === 0) return
    run(["add"].concat(words))
  }

  function markDone(uuid) { if (uuid) run([uuid, "done"]) }
  function remove(uuid) { if (uuid) run([uuid, "delete"]) }
  // One task tracks at a time: timew start closes the running interval, so the task that owned it stops too.
  function toggleActive(uuid, active) {
    if (!uuid) return
    if (active) { run([uuid, "stop"]); return }
    for (let i = 0; i < root.tasks.length; i++) if (root.tasks[i].active && root.tasks[i].uuid !== uuid) run([root.tasks[i].uuid, "stop"])
    run([uuid, "start"])
  }

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
    intervalMs: root.refreshMs
    onParsed: function (data) {
      root.tasks = root.buildTasks(data)
      root.loaded = true
      root.errorText = ""
      root.checkDue()
      root.exportDone()
    }
    onFailed: function (error) {
      // keep the last-good list: a transient export failure (a db lock from an overlapping poll) must not blank the widget
      root.loaded = true
      root.errorText = "task export failed"
      root.exportDone()
    }
  }

  JsonProcess {
    id: timewProc
    command: ["timew", "export", ":day"]
    intervalMs: root.refreshMs
    onParsed: function (data) { root.tracked = root.buildTracked(data) }
    onFailed: function (error) { }
  }

  Process {
    id: mutateProc
    stderr: StdioCollector { id: mutateErr; waitForEnd: true }
    onExited: function (exitCode) {
      root.errorText = exitCode === 0 ? "" : (String(mutateErr.text || "").trim().split("\n")[0] || "task exited " + exitCode)
      timewProc.refresh()
      root.mutateQueue.done()
      if (!root.mutateQueue.running) root.refresh()
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
