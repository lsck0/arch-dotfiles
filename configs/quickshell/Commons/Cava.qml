pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Audio spectrum source for the media visualizer: `cava` as a subprocess,
// parsed from its raw ASCII output. Quickshell has no FFT primitive of its
// own — `Quickshell.Services.Pipewire.PwNodePeakMonitor` gives real native
// peak metering with no subprocess, but that is a single "how loud right
// now" scalar, not per-band data, so it cannot drive distinct bars.
//
// Deliberately NOT a compiled C++ Quickshell plugin. caelestia ships one
// (Caelestia.Services.CavaProvider), which means rebuilding a .so against
// libcava and Quickshell headers on every Quickshell upgrade — a bad trade
// for six rectangles.
//
// Lives in Commons/ rather than services/ because Commons is the only real
// QML *module* here (`module qs.Commons` in its qmldir), and that is what
// makes a singleton actually singular. The lowercase services/ directory
// deliberately holds instances injected by shell.qml instead: relative-path
// singleton imports were creating one copy per importer — see
// services/BarWidgetRegistry.qml's header for that scar.
Singleton {
  id: root

  readonly property int barCount: 18

  // 0-100 per band, matching ascii_max_range below so a value maps straight
  // onto "percent of full bar height" with no scaling at the call site.
  property var values: [0, 0, 0, 0, 0, 0]

  property bool available: false

  // The whole idle-CPU story. The Process does not exist — no PID, no
  // polling, nothing — unless something is holding a reference. Take one
  // with a CavaRef, never by touching refCount directly.
  property int refCount: 0

  readonly property bool active: cavaProc.running

  // Its own config, never ~/.config/cava/config: this must not collide with
  // a terminal cava setup the user may keep separately.
  readonly property string confPath:
    (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-cava.conf"

  // sensitivity=300 with autosens=0 was measured, not guessed. Feeding
  // music-shaped noise through a null sink: sensitivity 30 (the value in
  // the research doc, inherited from DankMaterialShell, which re-normalises
  // in QML afterwards) peaked at 7/100 — a visualizer that never visibly
  // moves. 100 peaked at ~24, 300 at ~65, 450 clipped at 100. 300 leaves
  // headroom for louder material while still filling most of the bar.
  //
  // autosens stays 0 on purpose: automatic gain makes the bars visibly
  // recalibrate every time playback starts or stops.
  //
  // sleep_timer=3 is what makes cava itself go quiet after 3s of silence,
  // so idle CPU does not depend on QML noticing silence.
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
    "monstercat=1.5\n"

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
    running: root.available && root.refCount > 0

    // The config text is passed as an argv element rather than heredoc'd
    // into the script, so nothing in it can be re-interpreted by the shell.
    command: ["sh", "-c",
      "printf '%s' \"$1\" > \"$2\" && exec cava -p \"$2\"",
      "sh", root.configText, root.confPath]

    onRunningChanged: if (!running) root.values = root.zeroed()

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function (data) {
        if (root.refCount <= 0 || !data) return
        // cava emits a TRAILING semicolon, so a 6-bar frame splits into 7
        // parts with the last one empty. Read by index rather than
        // trusting the part count to equal barCount.
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
