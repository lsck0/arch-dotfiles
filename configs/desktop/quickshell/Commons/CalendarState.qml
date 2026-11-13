pragma Singleton
import QtQuick
import Quickshell

// The next three days' homelab calendar events (task-calendar events), for the agenda.
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
  // today's events are a cached or outdated answer (lab unreachable, calendar-sync stopped); the agenda says so
  property bool stale: false

  // ended events drop out between two fetches
  readonly property var events: {
    var out = []
    for (let i = 0; i < root.all.length; i++) {
      let e = root.all[i]
      // never time-drop an all-day event: its date-only start parses as UTC midnight and would vanish mid-day (and west of UTC); the next fetch retires it when the day rolls over
      let end = e.all_day ? NaN : Date.parse(e.end || e.start || "")
      if (!isNaN(end) && end <= root.nowMs) continue
      out.push({ summary: String(e.summary || ""), when: root.whenText(e), allDay: !!e.all_day, today: !!e.today,
                 marker: root.sourceMarker(e), markerColor: root.sourceColors[e.source] || Colors.textDim })
    }
    return out
  }

  // a source's colour in the agenda's marker column, none of the task markers' (urgent, warn, accent); one the map lacks stays dim
  readonly property var sourceColors: ({ uni: Colors.okText, work: Colors.foreground, proton: Colors.accent2Text })

  // the source label's initial (University, Work, Private), so the row says where it comes from without a legend
  function sourceMarker(e) {
    return String(e.source_label || e.source || ">").charAt(0).toUpperCase()
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
    command: [Paths.bin("task-calendar"), "events"]
    intervalMs: root.refreshMs
    minAgeMs: root.retryMs
    onParsed: function (data) {
      root.all = (data && data.events) ? Array.prototype.slice.call(data.events) : []
      root.stale = !!(data && data.stale)
      root.fetchedDate = new Date().toDateString()
      root.fetchFailed = false
    }
    onFailed: function (error) {
      root.fetchFailed = true
      console.warn("CalendarState: task-calendar failed:", error)
    }
  }
}
