pragma Singleton
import QtQuick
import Quickshell

// The next three days' homelab calendar events (task-calendar events), for the agenda.
Singleton {
  id: root

  readonly property int refreshMs: 10 * 60 * 1000
  // nobody looks at the events closely: the desktop agenda behind the windows makes do with a rarer fetch
  readonly property int refreshIdleMs: 30 * 60 * 1000
  // the open surfaces that list the events (the clock panel); each counts itself in and out
  property int viewers: 0
  onViewersChanged: if (viewers > 0) calendarProc.refresh()
  // after a failed or empty fetch the rollover check retries at most this often between polls
  readonly property int retryMs: 5 * 60 * 1000
  property var all: []
  property real nowMs: Date.now()
  // local date the events in `all` were fetched for; a rollover past it re-fetches so day labels and all-day events follow the new day
  property string fetchedDate: ""
  property bool fetchFailed: false
  // today's events are a cached or outdated answer (lab unreachable, calendar-sync stopped); the agenda says so
  property bool stale: false

  // the local date as the fetch's date-only all-day bounds spell it
  function dateKey(date) {
    return date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0") + "-" + String(date.getDate()).padStart(2, "0")
  }

  // past a rollover the fetch's `today` flags name the old day: all-day events retire at their exclusive end
  readonly property var events: {
    var out = []
    const now = new Date(root.nowMs)
    const rolledOver = root.fetchedDate !== "" && now.toDateString() !== root.fetchedDate
    const todayKey = dateKey(now)
    for (let i = 0; i < root.all.length; i++) {
      let e = root.all[i]
      // never time-drop an all-day event: its date-only start parses as UTC midnight and would vanish mid-day (and west of UTC)
      let end = e.all_day ? NaN : Date.parse(e.end || e.start || "")
      if (!isNaN(end) && end <= root.nowMs) continue
      if (rolledOver && e.all_day && String(e.end || "") <= todayKey) continue
      let startKey = e.all_day ? String(e.start || "") : dateKey(new Date(Date.parse(e.start || "")))
      let today = rolledOver ? startKey <= todayKey : !!e.today
      out.push({ summary: String(e.summary || ""), when: root.whenText(e, today), allDay: !!e.all_day, today: today,
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

  function whenText(e, today) {
    var day = today ? "" : String(e.day || "").slice(0, 3) + " "
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
    intervalMs: root.viewers > 0 ? root.refreshMs : root.refreshIdleMs
    minAgeMs: root.retryMs
    onParsed: function (data) {
      root.all = (data && data.events) ? Array.prototype.slice.call(data.events) : []
      root.stale = !!(data && data.stale)
      root.fetchedDate = new Date().toDateString()
      root.fetchFailed = false
    }
    onFailed: function (error) {
      root.fetchFailed = true
      root.stale = true
      console.warn("CalendarState: task-calendar failed:", error)
    }
  }
}
