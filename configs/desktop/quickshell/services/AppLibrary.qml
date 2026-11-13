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

  property var iconIndex: ({})
  property var pendingIconIndex: ({})

  property int launchSerial: 0
  property int launchToplevelCount: 0
  property var launchActiveToplevel: null
  property var lastActiveToplevel: null
  property bool launchOsdOpen: false
  property string launchOsdMessage: ""
  property string launchName: ""
  readonly property int launchNoticeMs: 3000

  signal appsChanged()

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
    onLoaded: root.frecency = Util.parseObject(text())
    onLoadFailed: root.frecency = ({})
  }

  function iconSource(icon) {
    var found = root.iconIndex[String(icon || "")]
    if (found && found.indexOf("/devices/") < 0) return Util.fileUrl(found)
    return Util.iconSource(icon) || (found ? Util.fileUrl(found) : "") || Quickshell.iconPath("application-x-executable", true)
  }

  function refreshIcons() {
    if (!iconIndexScan.running) iconIndexScan.running = true
  }

  function launch(desktopId, name) {
    var id = String(desktopId || "")
    if (!id) return
    root.recordLaunch(id)
    root.beginLaunchFeedback(name)
    var argv = ["uwsm-app", "--", "gtk-launch", id + ".desktop"]
    // gtk-launch returns once the app is spawned; a second launch inside that moment goes without the exit check
    if (launchProc.running) {
      Quickshell.execDetached(argv)
      return
    }
    launchProc.serial = root.launchSerial
    launchProc.command = argv
    launchProc.running = true
  }

  function parseIdSet(rawText) {
    var next = ({})
    for (const line of String(rawText || "").split("\n")) {
      const id = line.trim().replace(/\.desktop$/, "")
      if (id.length > 0) next[id] = true
    }
    return next
  }

  function iconIndexScanCommand() {
    return [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
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
    root.launchActiveToplevel = root.lastActiveToplevel
    root.launchName = String(name || "application")
    root.launchOsdMessage = "Launching " + root.launchName + "..."
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

  // replaces the launching OSD in place: a close followed by a present could land in either order
  function failLaunchFeedback(serial, message) {
    if (serial !== root.launchSerial) return
    launchDelay.stop()
    launchTimeout.stop()
    root.launchOsdOpen = false
    Quickshell.execDetached(Paths.ipcCall("osd", "present",
      JSON.stringify({ icon: "launch", message: message, duration: root.launchNoticeMs })))
  }

  function launchSettled() {
    if (root.toplevelCount() > root.launchToplevelCount) return true
    var active = ToplevelManager.activeToplevel
    return active !== null && active !== root.launchActiveToplevel
  }

  function maybeFinishLaunchFeedback() {
    if (!launchDelay.running && !launchTimeout.running && !root.launchOsdOpen) return
    if (root.launchSettled()) root.closeLaunchFeedback(root.launchSerial)
  }

  Process {
    id: hiddenEntryScan
    command: [Paths.shellDir + "/services/hidden-entries.nu", root.sessionDesktops]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.desktopHiddenEntryIds = root.parseIdSet(text)
        root.appsChanged()
      }
    }
  }

  Process {
    id: iconIndexScan
    command: ["bash", "-c", root.iconIndexScanCommand()]
    stdout: SplitParser { onRead: function(line) { root.indexIconLine(line) } }
    onStarted: root.pendingIconIndex = ({})
    onExited: {
      root.iconIndex = root.pendingIconIndex
      root.appsChanged()
    }
  }

  Process {
    id: launchProc
    property int serial: 0
    onExited: function(code) {
      if (code !== 0) root.failLaunchFeedback(launchProc.serial, root.launchName + " failed to start")
    }
  }

  Timer {
    id: rescanDebounce
    interval: 750
    onTriggered: {
      root.refreshIcons()
      if (!hiddenEntryScan.running) hiddenEntryScan.running = true
    }
  }

  WatchedFile {
    path: Paths.state + "/launcher.hides"
    onLoaded: {
      root.configuredHiddenEntryIds = root.parseIdSet(text())
      root.appsChanged()
    }
    onLoadFailed: {
      root.configuredHiddenEntryIds = ({})
      root.appsChanged()
    }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.maybeFinishLaunchFeedback() }
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() {
      if (ToplevelManager.activeToplevel !== null) root.lastActiveToplevel = ToplevelManager.activeToplevel
      root.maybeFinishLaunchFeedback()
    }
  }

  Timer {
    id: launchDelay
    interval: 2000
    onTriggered: {
      if (root.launchSettled()) return
      root.launchOsdOpen = true
      Quickshell.execDetached(Paths.ipcCall("osd", "present",
        JSON.stringify({ icon: "launch", message: root.launchOsdMessage, duration: 0 })))
    }
  }

  Timer {
    id: launchTimeout
    interval: 15000
    // a tray-only app opens no window either, so the wording stays neutral
    onTriggered: {
      if (root.launchSettled()) root.closeLaunchFeedback(root.launchSerial)
      else root.failLaunchFeedback(root.launchSerial, "No window from " + root.launchName)
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      rescanDebounce.restart()
      root.appsChanged()
    }
  }

  Component.onCompleted: {
    root.lastActiveToplevel = ToplevelManager.activeToplevel
    hiddenEntryScan.running = true
    iconIndexScan.running = true
  }
}
