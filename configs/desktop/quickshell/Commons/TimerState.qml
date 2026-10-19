pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// countdowns tick in qml off the absolute end time, never a per-second script fork
Singleton {
  id: root

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string pomoPath: runtimeDir + "/quickshell-pomodoro/state.json"
  readonly property string reminderIndexPath: runtimeDir + "/quickshell-reminders/index.json"
  readonly property string pomoConfigPath: Paths.home + "/.config/quickshell/pomodoro.json"

  readonly property string pomoScript: Paths.script("pomodoro.nu")
  readonly property string reminderScript: Paths.script("reminder.nu")

  // mirrors pomodoro.nu config_default, until the module first writes the file
  readonly property var pomoConfigDefault: ({ focus: 25, break: 5, long: 15, cycles: 4 })
  property var pomoConfig: pomoConfigDefault

  property bool overlayOpen: false

  property var pomoState: ({})
  property var reminderList: []

  property double nowSec: Math.floor(Date.now() / 1000)

  // the scripts write asynchronously and a fresh file may be missed by the watch, so ping a reload on every action
  function reload() { reloadTimer.restart() }
  function runPomo(args) { Quickshell.execDetached([root.pomoScript].concat(args)); reload() }
  function runReminder(args) { Quickshell.execDetached([root.reminderScript].concat(args)); reload() }

  // dot set takes seconds and its first write may be missed by the watch, so re-read once it exited
  property var pomoSetQueued: ({})
  readonly property bool pomoSaving: pomoSetProc.running
  function setPomoConfig(changes) {
    root.pomoSetQueued = Object.assign({}, root.pomoSetQueued, changes)
    if (!pomoSetProc.running) pomoSetNext()
  }

  function pomoSetNext() {
    var argv = [root.pomoScript, "set"]
    for (const key in root.pomoSetQueued) argv.push(key, String(root.pomoSetQueued[key]))
    root.pomoSetQueued = ({})
    if (argv.length === 2) return false
    pomoSetProc.command = argv
    pomoSetProc.running = true
    return true
  }

  function applyPomoConfig(txt) {
    var read = {}
    try { read = JSON.parse(txt || "{}") || {} } catch (e) {}
    root.pomoConfig = Object.assign({}, root.pomoConfigDefault, read)
  }

  function applyPomo(txt) {
    try { root.pomoState = JSON.parse(txt || "{}") || ({}) } catch (e) { root.pomoState = ({}) }
    root.nowSec = Math.floor(Date.now() / 1000)
  }

  function applyReminders(txt) {
    try { root.reminderList = JSON.parse(txt || "{}").reminders || [] } catch (e) { root.reminderList = [] }
    root.nowSec = Math.floor(Date.now() / 1000)
  }

  // matches reminder.nu remaining-format
  function remainingText(seconds) {
    var s = Math.max(0, Math.floor(seconds))
    var m = Math.floor(s / 60)
    var r = s % 60
    if (m > 0 && r > 0) return m + "m " + r + "s"
    if (m > 0) return m + "m"
    return r + "s"
  }

  readonly property bool pomoRunning: !!pomoState.running
  readonly property bool pomoPaused: !!pomoState.paused
  readonly property bool pomoTicking: pomoRunning && !pomoPaused

  readonly property int pomoRemainingSeconds: {
    if (!pomoRunning) return 0
    var left = pomoPaused ? Number(pomoState.remaining || 0) : Number(pomoState.endsAt || 0) - nowSec
    return Math.max(0, Math.floor(left))
  }

  readonly property int pomoTotalSeconds: {
    if (!pomoRunning) return 0
    var mins = pomoState.phase === "work" ? Number(pomoState.work || 0)
             : pomoState.phase === "long" ? Number(pomoState.long || 0) : Number(pomoState["break"] || 0)
    return mins * 60
  }

  readonly property string pomoPhaseLabel: pomoState.phase === "work" ? "Focus"
    : pomoState.phase === "long" ? "Long break" : "Break"

  readonly property string pomoTooltip: pomoRunning
    ? pomoPhaseLabel + " :: " + Util.clock(pomoRemainingSeconds) + " left :: pomodoro " + Number(pomoState.cycle || 0)
      + (pomoPaused ? " (paused)" : "")
    : "Pomodoro: off"

  readonly property var pomo: ({
    running: pomoRunning,
    paused: pomoPaused,
    phase: String(pomoState.phase || "idle"),
    remaining: pomoRunning ? Util.clock(pomoRemainingSeconds) : "",
    remainingSeconds: pomoRemainingSeconds,
    totalSeconds: pomoTotalSeconds,
    cycle: Number(pomoState.cycle || 0),
    longEvery: Number(pomoRunning && pomoState.cycles ? pomoState.cycles : pomoConfig.cycles),
    defaultWork: Number(pomoConfig.focus),
    tooltip: pomoTooltip
  })

  readonly property var reminders: {
    var out = []
    var list = reminderList || []
    for (let i = 0; i < list.length; i++) {
      let at = Number(list[i].at || 0)
      if (at <= nowSec) continue
      out.push({ unit: list[i].unit, label: list[i].label, atTime: list[i].atTime, remaining: remainingText(at - nowSec) })
    }
    return out
  }

  readonly property int reminderCount: reminders.length
  readonly property string reminderTooltip: reminderCount === 0 ? "Set Reminder"
    : reminderCount === 1 ? "1 reminder" : reminderCount + " reminders"

  Timer {
    interval: 1000
    running: root.overlayOpen || root.pomoTicking
    repeat: true
    triggeredOnStart: true
    onTriggered: root.nowSec = Math.floor(Date.now() / 1000)
  }

  Timer { id: reloadTimer; interval: 250; onTriggered: { pomoFile.reload(); reminderFile.reload() } }

  FileView {
    id: pomoFile
    path: root.pomoPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.applyPomo(text()); Util.rearmWatch(this) }
    onLoadFailed: root.pomoState = ({})
    onFileChanged: reload()
  }

  Process {
    id: pomoSetProc
    onExited: if (!root.pomoSetNext()) pomoConfigFile.reload()
  }

  FileView {
    id: pomoConfigFile
    path: root.pomoConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.applyPomoConfig(text()); Util.rearmWatch(this) }
    onLoadFailed: root.applyPomoConfig("")
    onFileChanged: reload()
  }

  FileView {
    id: reminderFile
    path: root.reminderIndexPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.applyReminders(text()); Util.rearmWatch(this) }
    onLoadFailed: root.reminderList = []
    onFileChanged: reload()
  }
}
