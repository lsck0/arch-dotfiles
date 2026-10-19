pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  readonly property int barCount: 24
  readonly property int framerate: 60

  property var values: zeroed()

  property var peaks: zeroed()

  // cava runs with little noise reduction so a hit lands on the next frame; the fall is smoothed here instead
  readonly property real releaseKeep: 0.72
  readonly property int peakHoldFrames: Math.round(framerate * 0.2)
  readonly property real peakFallPerFrame: 100 / (framerate * 0.6)
  property var peakAge: zeroed()

  property bool available: false

  property int refCount: 0

  // own config, never the user's ~/.config/cava; no /tmp fallback, the write would follow a planted symlink
  readonly property string confPath:
    Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") + "/quickshell-cava.conf" : ""

  property string source: ""

  // cava reads its config once, so restart on change
  onSourceChanged: restart()

  function restart() {
    if (!cavaProc.running) return
    cavaProc.running = false
    cavaProc.running = Qt.binding(function() { return root.available && root.confPath !== "" && root.refCount > 0 && !Power.saver })
  }

  readonly property string configText:
    "[general]\n" +
    "framerate=" + framerate + "\n" +
    "bars=" + barCount + "\n" +
    "autosens=1\n" +
    "sensitivity=100\n" +
    "sleep_timer=3\n" +
    "lower_cutoff_freq=40\n" +
    "higher_cutoff_freq=12000\n" +
    "\n[output]\n" +
    "method=raw\n" +
    "raw_target=/dev/stdout\n" +
    "data_format=ascii\n" +
    "ascii_max_range=100\n" +
    "channels=mono\n" +
    "mono_option=average\n" +
    "\n[smoothing]\n" +
    "noise_reduction=12\n" +
    "monstercat=0\n" +
    "waves=0\n" +
    (source ? "\n[input]\nmethod=pipewire\nsource=" + source + "\n" : "")

  function zeroed() {
    var out = []
    for (let i = 0; i < barCount; i++) out.push(0)
    return out
  }

  function reset() {
    values = zeroed()
    peaks = zeroed()
    peakAge = zeroed()
  }

  Process {
    running: true
    command: ["sh", "-c", "command -v cava >/dev/null 2>&1 && echo yes || echo no"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.available = String(text || "").trim() === "yes"
        if (!root.available) console.warn("Cava: `cava` not found; media visualizer disabled")
      }
    }
  }

  Process {
    id: cavaProc
    running: root.available && root.confPath !== "" && root.refCount > 0 && !Power.saver

    // config via argv so the shell never interprets it
    command: ["sh", "-c",
      "printf '%s' \"$1\" > \"$2\" && exec cava -p \"$2\"",
      "sh", root.configText, root.confPath]

    onRunningChanged: if (!running) root.reset()

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function (data) {
        if (root.refCount <= 0 || !data) return
        var parts = data.split(";")
        if (parts.length < root.barCount) return
        var prev = root.values, prevPeak = root.peaks, prevAge = root.peakAge
        var out = [], pk = [], age = []
        for (let i = 0; i < root.barCount; i++) {
          let raw = parseInt(parts[i], 10)
          raw = isNaN(raw) ? 0 : Math.max(0, Math.min(100, raw))
          let v = raw >= prev[i] ? raw : prev[i] * root.releaseKeep + raw * (1 - root.releaseKeep)
          out.push(v)
          if (v >= prevPeak[i]) {
            pk.push(v)
            age.push(0)
          } else if (prevAge[i] < root.peakHoldFrames) {
            pk.push(prevPeak[i])
            age.push(prevAge[i] + 1)
          } else {
            pk.push(Math.max(v, prevPeak[i] - root.peakFallPerFrame))
            age.push(prevAge[i] + 1)
          }
        }
        root.values = out
        root.peaks = pk
        root.peakAge = age
      }
    }
  }
}
