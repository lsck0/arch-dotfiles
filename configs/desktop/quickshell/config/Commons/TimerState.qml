pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  readonly property string pomoPath: Paths.runtimeDir + "/quickshell-pomodoro/state.json"
  readonly property string reminderIndexPath: Paths.runtimeDir + "/quickshell-reminders/index.json"
  readonly property string pomoConfigPath: Paths.home + "/.config/quickshell/pomodoro.json"

  readonly property string pomoScript: Paths.script("pomodoro.nu")

  // fallback only; link always writes pomodoro.json from the pomodoro_* options in mod.nu
  readonly property var pomoConfigDefault: ({ focus: 25, break: 5, long: 15, cycles: 4 })
  property var pomoConfig: pomoConfigDefault

  property bool overlayOpen: false

  property var pomoState: ({})
  property var reminderList: []

  property double nowSec: Math.floor(Date.now() / 1000)

  function reload() { reloadTimer.restart() }

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
    root.pomoConfig = Object.assign({}, root.pomoConfigDefault, Util.parseObject(txt))
  }

  function applyPomo(txt) {
    root.pomoState = Util.parseObject(txt)
    root.nowSec = Math.floor(Date.now() / 1000)
  }

  function applyReminders(txt) {
    root.reminderList = Util.parseObject(txt).reminders || []
    root.nowSec = Math.floor(Date.now() / 1000)
  }

  function remainingText(seconds) {
    var s = Math.max(0, Math.floor(seconds))
    var units = [[86400, "d"], [3600, "h"], [60, "m"], [1, "s"]]
    var i = units.findIndex(function (u) { return s >= u[0] })
    if (i < 0 || i === units.length - 1) return s + "s"
    var big = Math.floor(s / units[i][0]) + units[i][1]
    var rest = Math.floor(s % units[i][0] / units[i + 1][0])
    return rest > 0 ? big + " " + rest + units[i + 1][1] : big
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

  readonly property var pomo: ({
    running: pomoRunning,
    paused: pomoPaused,
    phase: String(pomoState.phase || "idle"),
    remaining: pomoRunning ? Util.clock(pomoRemainingSeconds) : "",
    remainingSeconds: pomoRemainingSeconds,
    totalSeconds: pomoTotalSeconds,
    cycle: Number(pomoState.cycle || 0),
    longEvery: Number(pomoRunning && pomoState.cycles ? pomoState.cycles : pomoConfig.cycles),
    defaultWork: Number(pomoConfig.focus)
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

  // remainingText shows seconds only below this; a reminder further out needs a tick a minute, not a second
  readonly property int secondsShownBelowS: 3600
  readonly property real soonestReminderS: {
    var soonest = Infinity
    for (const reminder of reminderList || []) {
      const left = Number(reminder.at || 0) - nowSec
      if (left > 0) soonest = Math.min(soonest, left)
    }
    return soonest
  }

  // Reminders show their countdown on the desktop and in the tasks panel too, not only in the overlay. The switch to
  // second ticks looks one minute tick ahead, since nowSec only moves when this timer fires.
  Timer {
    interval: root.overlayOpen || root.pomoTicking || root.soonestReminderS - 60 < root.secondsShownBelowS ? 1000 : 60000
    running: root.overlayOpen || root.pomoTicking || root.reminderList.length > 0
    repeat: true
    triggeredOnStart: true
    onTriggered: root.nowSec = Math.floor(Date.now() / 1000)
  }

  Timer { id: reloadTimer; interval: 250; onTriggered: { pomoFile.reload(); reminderFile.reload() } }

  WatchedFile {
    id: pomoFile
    path: root.pomoPath
    onLoaded: root.applyPomo(text())
    onLoadFailed: root.pomoState = ({})
  }

  Process {
    id: pomoSetProc
    onExited: if (!root.pomoSetNext()) pomoConfigFile.reload()
  }

  WatchedFile {
    id: pomoConfigFile
    path: root.pomoConfigPath
    onLoaded: root.applyPomoConfig(text())
    onLoadFailed: root.applyPomoConfig("")
  }

  WatchedFile {
    id: reminderFile
    path: root.reminderIndexPath
    onLoaded: root.applyReminders(text())
    onLoadFailed: root.reminderList = []
  }
}
