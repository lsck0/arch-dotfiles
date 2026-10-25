pragma Singleton
import QtQuick
import Quickshell

// Today's and tomorrow's homelab calendar events (task-calendar events), for the agenda.
Singleton {
  id: root

  readonly property int refreshMs: 10 * 60 * 1000
  property var all: []
  property real nowMs: Date.now()

  // ended events drop out between two fetches
  readonly property var events: {
    var out = []
    for (let i = 0; i < root.all.length; i++) {
      let e = root.all[i]
      let end = Date.parse(e.end || e.start || "")
      if (!isNaN(end) && end <= root.nowMs) continue
      out.push({ summary: String(e.summary || ""), when: root.whenText(e) })
    }
    return out
  }

  function whenText(e) {
    var day = e.today ? "" : String(e.day || "").slice(0, 3) + " "
    return day + (e.all_day ? "all day" : String(e.time || ""))
  }

  Timer { interval: 60000; running: true; repeat: true; onTriggered: root.nowMs = Date.now() }

  JsonProcess {
    command: [Paths.home + "/.local/bin/task-calendar", "events"]
    intervalMs: root.refreshMs
    onParsed: function (data) { root.all = (data && data.events) ? Array.prototype.slice.call(data.events) : [] }
    onFailed: function (error) { }
  }
}
