import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "AppSearch.js" as AppSearch

Item {
  id: root

  property var configuredHiddenEntryIds: ({})
  property var desktopHiddenEntryIds: ({})

  // fallback for icons installed after qt cached its theme
  property var iconIndex: ({})
  property var pendingIconIndex: ({})

  property int launchSerial: 0
  property int launchToplevelCount: 0
  property var launchActiveToplevel: null
  property bool launchOsdOpen: false
  property string launchOsdMessage: ""

  signal appsChanged()

  function entryName(entry) {
    return AppSearch.entryName(entry)
  }

  function entrySubtext(entry) {
    return AppSearch.entrySubtext(entry)
  }

  function isHiddenEntry(entry) {
    var id = String((entry && entry.id) || "")
    return root.configuredHiddenEntryIds[id] === true || root.desktopHiddenEntryIds[id] === true
  }

  function sortedEntries(query) {
    var values = DesktopEntries.applications.values || []
    var now = Date.now()
    return AppSearch.sortedEntries(values, query,
      function(entry) { return root.isHiddenEntry(entry) },
      function(entry) { return AppSearch.frecencyRank(root.frecency[String(entry.id || "")], now) })
  }

  // launcher frecency, { desktopId: { n: launches, t: last ms } }
  property var frecency: ({})

  function recordLaunch(id) {
    root.frecency = AppSearch.frecencyBump(root.frecency, String(id), Date.now())
    frecencyFile.setText(JSON.stringify(root.frecency) + "\n")
  }

  FileView {
    id: frecencyFile
    path: Paths.state + "/launcher-frecency.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text() || "{}")
        root.frecency = Util.isPlainObject(parsed) ? parsed : ({})
      } catch (e) {
        // corrupt state only costs the ranking
        root.frecency = ({})
      }
    }
    onLoadFailed: root.frecency = ({})
  }

  function iconSource(icon) {
    var found = root.iconIndex[String(icon || "")]
    return (found ? Util.fileUrl(found) : Util.iconSource(icon)) || Quickshell.iconPath("application-x-executable", true)
  }

  function refreshIcons() {
    if (!iconIndexScan.running) iconIndexScan.running = true
  }

  function launch(desktopId, name) {
    var id = String(desktopId || "")
    if (!id) return
    root.recordLaunch(id)
    root.beginLaunchFeedback(name)
    // uwsm-app so apps do not inherit wayland-wm@.service
    Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", id + ".desktop"])
  }

  function normalizeDesktopId(id) {
    var value = String(id || "").trim()
    if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
    return value
  }

  function parseIdSet(rawText) {
    var next = ({})
    var lines = String(rawText || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = root.normalizeDesktopId(lines[i])
      if (id.length > 0) next[id] = true
    }
    return next
  }

  function loadConfiguredHides(rawText) {
    root.configuredHiddenEntryIds = root.parseIdSet(rawText)
    root.appsChanged()
  }

  function loadDesktopHiddenEntries(rawText) {
    root.desktopHiddenEntryIds = root.parseIdSet(rawText)
    root.appsChanged()
  }

  function iconIndexScanCommand() {
    return [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      // ${d%/} avoids doubled slashes from XDG_DATA_DIRS
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs ${d%/}/icons"; done; unset IFS;',
      'for ext in svg png; do',
      '  for base in $dirs; do',
      '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.$ext" 2>/dev/null;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
      'done'
    ].join(' ')
  }

  function indexIconLine(path) {
    var value = String(path || "").trim()
    if (value.length === 0) return
    var slash = value.lastIndexOf("/")
    var file = slash >= 0 ? value.slice(slash + 1) : value
    var dot = file.lastIndexOf(".")
    var name = dot > 0 ? file.slice(0, dot) : file
    if (name.length > 0 && root.pendingIconIndex[name] === undefined)
      root.pendingIconIndex[name] = value
  }

  readonly property string sessionDesktops: [
    Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")
  ].filter(function(v) { return String(v || "").length > 0 }).join(":")

  function toplevelCount() {
    try { return ToplevelManager.toplevels.values.length } catch (e) { return 0 }
  }

  function beginLaunchFeedback(name) {
    root.launchSerial++
    root.launchToplevelCount = root.toplevelCount()
    root.launchActiveToplevel = ToplevelManager.activeToplevel
    root.launchOsdMessage = "Launching " + String(name || "application") + "..."
    launchDelay.restart()
    launchTimeout.restart()
  }

  function closeLaunchFeedback(serial) {
    if (serial !== root.launchSerial) return
    launchDelay.stop()
    launchTimeout.stop()
    if (root.launchOsdOpen) {
      Quickshell.execDetached(Paths.ipcCall("osd", "close"))
      root.launchOsdOpen = false
    }
  }

  function maybeFinishLaunchFeedback() {
    if (!launchDelay.running && !launchTimeout.running && !root.launchOsdOpen) return
    if (root.toplevelCount() <= root.launchToplevelCount && ToplevelManager.activeToplevel === root.launchActiveToplevel) return
    root.closeLaunchFeedback(root.launchSerial)
  }

  Process {
    id: hiddenEntryScan
    command: ["bash", Paths.shellDir + "/services/hidden-entries.sh", root.sessionDesktops]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadDesktopHiddenEntries(text)
    }
  }

  Process {
    id: iconIndexScan
    command: ["bash", "-c", root.iconIndexScanCommand()]
    stdout: SplitParser { onRead: function(line) { root.indexIconLine(line) } }
    onStarted: root.pendingIconIndex = ({})
    // swapping the map re-evaluates every iconSource() binding
    onExited: root.iconIndex = root.pendingIconIndex
  }

  // coalesce bursts of app-list changes
  Timer {
    id: iconIndexDebounce
    interval: 750
    onTriggered: if (!iconIndexScan.running) iconIndexScan.running = true
  }

  Timer {
    id: hiddenEntryDebounce
    interval: 750
    onTriggered: if (!hiddenEntryScan.running) hiddenEntryScan.running = true
  }

  FileView {
    path: Paths.state + "/launcher.hides"
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.loadConfiguredHides(text())
      Util.rearmWatch(this)
    }
    onFileChanged: reload()
    onLoadFailed: root.loadConfiguredHides("")
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.maybeFinishLaunchFeedback() }
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.maybeFinishLaunchFeedback() }
  }

  Timer {
    id: launchDelay
    interval: 2000
    onTriggered: {
      if (root.toplevelCount() > root.launchToplevelCount || ToplevelManager.activeToplevel !== root.launchActiveToplevel) return
      root.launchOsdOpen = true
      Quickshell.execDetached(Paths.ipcCall("osd", "present",
        JSON.stringify({ icon: "launch", message: root.launchOsdMessage, duration: 0 })))
    }
  }

  Timer {
    id: launchTimeout
    interval: 15000
    onTriggered: root.closeLaunchFeedback(root.launchSerial)
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      hiddenEntryDebounce.restart()
      iconIndexDebounce.restart()
      root.appsChanged()
    }
  }

  Component.onCompleted: {
    hiddenEntryScan.running = true
    iconIndexScan.running = true
  }
}
