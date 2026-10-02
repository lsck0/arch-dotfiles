pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// spectrum for the media visualizer from cava's raw ascii output
Singleton {
  id: root

  readonly property int barCount: 24

  // 0-100 per band, see ascii_max_range
  property var values: zeroed()

  property bool available: false

  // cava only runs while referenced
  property int refCount: 0

  // own config, never the user's ~/.config/cava
  readonly property string confPath:
    (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-cava.conf"

  property string source: ""

  // cava reads its config once, so restart on change
  onSourceChanged: restart()

  function restart() {
    if (!cavaProc.running) return
    cavaProc.running = false
    cavaProc.running = Qt.binding(function() { return root.available && root.refCount > 0 && !Power.saver })
  }

  readonly property string configText:
    "[general]\n" +
    "framerate=25\n" +
    "bars=" + barCount + "\n" +
    "autosens=0\n" +
    "sensitivity=450\n" +
    "sleep_timer=3\n" +
    "lower_cutoff_freq=50\n" +
    "higher_cutoff_freq=12000\n" +
    "\n[output]\n" +
    "method=raw\n" +
    "raw_target=/dev/stdout\n" +
    "data_format=ascii\n" +
    "ascii_max_range=100\n" +
    "channels=mono\n" +
    "mono_option=average\n" +
    "\n[smoothing]\n" +
    "noise_reduction=35\n" +
    "integral=90\n" +
    "gravity=95\n" +
    "ignore=2\n" +
    "monstercat=1.5\n" +
    (source ? "\n[input]\nmethod=pipewire\nsource=" + source + "\n" : "")

  function zeroed() {
    var out = []
    for (var i = 0; i < barCount; i++) out.push(0)
    return out
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
    running: root.available && root.refCount > 0 && !Power.saver

    // config via argv so the shell never interprets it
    command: ["sh", "-c",
      "printf '%s' \"$1\" > \"$2\" && exec cava -p \"$2\"",
      "sh", root.configText, root.confPath]

    onRunningChanged: if (!running) root.values = root.zeroed()

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function (data) {
        if (root.refCount <= 0 || !data) return
        // trailing semicolon yields one extra empty part
        var parts = data.split(";")
        if (parts.length < root.barCount) return
        var out = []
        for (var i = 0; i < root.barCount; i++) {
          var v = parseInt(parts[i], 10)
          out.push(isNaN(v) ? 0 : Math.max(0, Math.min(100, v)))
        }
        root.values = out
      }
    }
  }
}
