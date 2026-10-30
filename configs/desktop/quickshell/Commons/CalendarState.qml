pragma Singleton
import QtQuick
import Quickshell

// Today's and tomorrow's homelab calendar events (task-calendar events), for the agenda.
Singleton {
  id: root

  readonly property int refreshMs: 10 * 60 * 1000
  // after a failed or empty fetch the rollover check retries at most this often between polls
  readonly property int retryMs: 5 * 60 * 1000
  property var all: []
  property real nowMs: Date.now()
  // local date the events in `all` were fetched for; a rollover past it re-fetches so day labels and all-day events follow the new day
  property string fetchedDate: ""
  property bool fetchFailed: false

  // ended events drop out between two fetches
  readonly property var events: {
    var out = []
    for (let i = 0; i < root.all.length; i++) {
      let e = root.all[i]
      // never time-drop an all-day event: its date-only start parses as UTC midnight and would vanish mid-day (and west of UTC); the next fetch retires it when the day rolls over
      let end = e.all_day ? NaN : Date.parse(e.end || e.start || "")
      if (!isNaN(end) && end <= root.nowMs) continue
      out.push({ summary: String(e.summary || ""), when: root.whenText(e) })
    }
    return out
  }

  function whenText(e) {
    var day = e.today ? "" : String(e.day || "").slice(0, 3) + " "
    return day + (e.all_day ? "all day" : String(e.time || ""))
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      root.nowMs = Date.now()
      if (new Date().toDateString() === root.fetchedDate) return
      if (root.fetchFailed) calendarProc.refresh()
      else calendarProc.run()
    }
  }

  JsonProcess {
    id: calendarProc
    command: [Paths.home + "/.local/bin/task-calendar", "events"]
    intervalMs: root.refreshMs
    minAgeMs: root.retryMs
    onParsed: function (data) {
      root.all = (data && data.events) ? Array.prototype.slice.call(data.events) : []
      root.fetchedDate = new Date().toDateString()
      root.fetchFailed = false
    }
    onFailed: function (error) {
      root.fetchFailed = true
      console.warn("CalendarState: task-calendar failed:", error)
    }
  }
}
