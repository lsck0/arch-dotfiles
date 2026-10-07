pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// single owner of pomodoro + reminder state; pomodoro.sh and reminder.sh mutate the files, this derives the live view
// the running countdown is a 1Hz QML tick off the absolute end time, never a per-second script fork
Singleton {
  id: root

  // the scripts' runtime state, gone on boot
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string pomoPath: runtimeDir + "/quickshell-pomodoro/state.json"
  readonly property string reminderIndexPath: runtimeDir + "/quickshell-reminders/index.json"

  readonly property string pomoScript: Paths.script("pomodoro.sh")
  readonly property string reminderScript: Paths.script("reminder.sh")

  // mirror pomodoro.sh DEF_WORK / LONG_EVERY, only shown while idle
  readonly property int pomoDefaultWorkMin: 25
  readonly property int pomoLongEvery: 4

  // the reminders overlay sets this while open so its per-reminder countdowns tick
  property bool overlayOpen: false

  // raw file-backed state
  property var pomoState: ({})
  property var reminderList: []

  // unix seconds, stepped by the 1Hz tick while something counts down
  property double nowSec: Math.floor(Date.now() / 1000)

  // the scripts write asynchronously and a fresh file may be missed by the watch, so ping a reload on every action
  function reload() { reloadTimer.restart() }
  function runPomo(args) { Quickshell.execDetached([root.pomoScript].concat(args)); reload() }
  function runReminder(args) { Quickshell.execDetached([root.reminderScript].concat(args)); reload() }

  function applyPomo(txt) {
    try { root.pomoState = JSON.parse(txt || "{}") || ({}) } catch (e) { root.pomoState = ({}) }
    root.nowSec = Math.floor(Date.now() / 1000)
  }

  function applyReminders(txt) {
    try { root.reminderList = JSON.parse(txt || "{}").reminders || [] } catch (e) { root.reminderList = [] }
    root.nowSec = Math.floor(Date.now() / 1000)
  }

  // "5m 3s", "5m", "3s" like reminder.sh format_remaining
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

  // paused freezes the leftover, else it counts down from the absolute end
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

  // the shape the overlay, Clock and the indicator read, recomputed as the tick and the files move
  readonly property var pomo: ({
    running: pomoRunning,
    paused: pomoPaused,
    phase: String(pomoState.phase || "idle"),
    remaining: pomoRunning ? Util.clock(pomoRemainingSeconds) : "",
    remainingSeconds: pomoRemainingSeconds,
    totalSeconds: pomoTotalSeconds,
    cycle: Number(pomoState.cycle || 0),
    longEvery: pomoLongEvery,
    defaultWork: pomoDefaultWorkMin,
    tooltip: pomoTooltip
  })

  // drop reminders whose absolute fire time has passed, expose a live remaining string
  readonly property var reminders: {
    var out = []
    var list = reminderList || []
    for (var i = 0; i < list.length; i++) {
      var at = Number(list[i].at || 0)
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
