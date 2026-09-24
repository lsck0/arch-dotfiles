import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

/*
 * ─────────────────────────────────────────────────────────────────────────────
 * PowerModeSelector — the TLP power-profile chip row
 * ─────────────────────────────────────────────────────────────────────────────
 *
 * WHAT IT IS. The whole power-mode control: the option list, the reader, the
 * writer, and the ButtonGroup that shows them. Drop it in a panel and it works.
 *
 *   PowerModeSelector {
 *     width: parent.width
 *     active: panel.visible     // read the backend only while on screen
 *   }
 *
 * WHY IT EXISTS. System.qml and Battery.qml each carried their own copy of
 * `powerMode`, `powerModeScript`, `refreshPowerMode()`, `setPowerMode()`, a
 * `Process`, a 5s `Timer` and the option array — ~35 identical lines twice, and
 * they had already drifted: System grew the "Auto" chip for the no-override
 * state and Battery never did, so the same setting rendered with nothing
 * selected in one panel and correctly in the other. One definition cannot
 * disagree with itself.
 *
 * WHAT IT DOES NOT DO. It does not own the setting. toggles/toggle-powermode.sh
 * is the single source of truth for power mode, here as everywhere else in this
 * repo; this reads it with `get` and writes it by invoking the script. Nothing
 * is cached across a `set`, the value is re-read from the backend.
 *
 * "" from the script means NO forced override — TLP is on the boot default from
 * configs/tlp/tlp.conf. That is a real state, not a missing reading, so it maps
 * onto a real "Auto" chip rather than leaving the group blank.
 */
Item {
  id: root

  // ─────────────────────────────────────────────────────────── CONSTANTS

  // The four states toggle-powermode.sh accepts.
  readonly property var modeOptions: [
    { value: "auto",        label: "Auto" },
    { value: "power-saver", label: "Power saver" },
    { value: "balanced",    label: "Balanced" },
    { value: "performance", label: "Performance" }
  ]

  // Catch-up poll for changes made outside this control — a keybind, toggles/menu.sh, another panel.
  readonly property int pollIntervalMs: 5000

  // Time for the detached script to fork, source lib.sh, call `sudo tlp` and write its volatile state file before the value is worth re-reading.
  readonly property int applySettleMs: 600

  // ─────────────────────────────────────────────────────────── API

  // Bind to the containing panel's visibility.
  property bool active: false

  // Palette + type, so a panel can match its surroundings.
  property color foreground: Color.menu.text
  property color background: "transparent"
  property real fontSize: Style.font.caption

  // Current mode as the script reports it. "" is no override (see header).
  readonly property alias mode: internal.mode

  readonly property string script: Paths.toggle("toggle-powermode.sh")

  function refresh() {
    if (!getProcess.running) getProcess.running = true
  }

  function apply(mode) {
    Quickshell.execDetached([root.script, String(mode)])
    settleTimer.restart()
  }

  implicitWidth: group.implicitWidth
  implicitHeight: group.implicitHeight

  // ─────────────────────────────────────────────────────────── INTERNAL

  QtObject {
    id: internal
    property string mode: ""
  }

  Process {
    id: getProcess
    command: [root.script, "get"]
    stdout: StdioCollector {
      id: getOutput
      waitForEnd: true
    }
    onExited: internal.mode = String(getOutput.text || "").trim()
  }

  Timer {
    id: settleTimer
    interval: root.applySettleMs
    onTriggered: root.refresh()
  }

  Timer {
    interval: root.pollIntervalMs
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  ButtonGroup {
    id: group
    width: root.width
    fill: true
    spacing: Style.spacing.xs
    options: root.modeOptions
    value: internal.mode === "" ? "auto" : internal.mode
    foreground: root.foreground
    background: root.background
    fontSize: root.fontSize
    onChanged: function(value) { root.apply(value) }
  }
}
