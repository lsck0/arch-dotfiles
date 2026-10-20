pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Hyprland
import qs.Commons

import "components"
import "NotificationLogic.js" as NotificationLogic

Item {
  id: service

  property var shell: null

  readonly property string stateDir: Paths.state + "/"
  readonly property string settingsPath: stateDir + "notifications.json"
  readonly property string popupStateDir: stateDir + "notifications/"
  readonly property string historyDir: popupStateDir + "history/"
  readonly property string imagesDir: popupStateDir + "images/"
  readonly property int barClearance: Style.bar.sizeHorizontal + Style.gapsOut
  readonly property int toastWidth: Style.space(420)

  // kept out of the model: stale qobject roles segfault
  property var liveRefs: ({})

  FileView {
    id: settingsFile
    path: service.settingsPath
    blockLoading: true
    atomicWrites: true
    printErrors: false
    onAdapterUpdated: writeAdapter()

    // quickshell's qmltypes stub FileViewAdapter
    JsonAdapter { // qmllint disable unresolved-type
      id: settings
      property bool dnd: false
      property bool dndByObs: false
    }
  }

  PersistentProperties {
    id: persisted
    reloadableId: "quickshell-notifications"
    property bool obsSession: false
  }

  readonly property alias doNotDisturb: settings.dnd

  function setDoNotDisturb(value) {
    // settings sits in FileView's opaque adapter slot
    settings.dndByObs = false // qmllint disable unqualified
    settings.dnd = !!value // qmllint disable unqualified
  }

  function obsSync() {
    if (!ObsProcess.probed) return
    if (ObsProcess.running && !persisted.obsSession) {
      persisted.obsSession = true
      if (!settings.dnd) { // qmllint disable unqualified
        settings.dndByObs = true // qmllint disable unqualified
        settings.dnd = true // qmllint disable unqualified
      }
    } else if (!ObsProcess.running) {
      if (settings.dndByObs) settings.dnd = false // qmllint disable unqualified
      settings.dndByObs = false // qmllint disable unqualified
      persisted.obsSession = false
    }
  }

  Connections {
    target: ObsProcess
    function onRunningChanged() { service.obsSync() }
    function onProbedChanged() { service.obsSync() }
  }

  ListModel { id: popupModel }

  readonly property int historyLimit: 30

  property double popupNowMs: Date.now()
  Timer {
    interval: 20000
    running: popupModel.count > 0
    repeat: true
    triggeredOnStart: true
    onTriggered: service.popupNowMs = Date.now()
  }

  readonly property var popupMinMs: [5000, 8000, 0]
  readonly property int popupMaxMs: 30000

  function durationFor(urgency, expireTimeout) {
    var minMs = popupMinMs[urgency] ?? popupMinMs[NotificationUrgency.Normal]
    return minMs && Math.min(popupMaxMs, Math.max(minMs, Number(expireTimeout) || 0))
  }

  function isEphemeral(notification) {
    var transient = false
    try {
      transient = !!(notification.hints && notification.hints["transient"])
    } catch (e) {
    }
    return transient || NotificationLogic.isEphemeralApp(String(notification.appName || ""))
  }

  function entryNameOf(notification) {
    var id = String(notification.desktopEntry || "")
    var entry = id ? DesktopEntries.byId(id) : null
    return entry ? String(entry.name || "") : ""
  }

  function snapshotOf(notification, originalId, timestamp) {
    return NotificationLogic.replacementSnapshot(notification, originalId, timestamp, entryNameOf(notification))
  }

  function handleNotification(notification) {
    notification.tracked = true
    var snapshot = NotificationLogic.snapshotOf(notification, Date.now(), entryNameOf(notification))
    var originalId = snapshot.originalId
    liveRefs[originalId] = notification
    notification.closed.connect(function() {
      if (service.liveRefs[originalId] !== notification) return
      delete service.liveRefs[originalId]
      // the sender closed it (CloseNotification): its popup goes too, the history keeps it
      Qt.callLater(function() { service.closePopupsByOriginalId(originalId) })
    })

    if (service.doNotDisturb && !NotificationLogic.shouldBypassDnd(notification)) {
      if (isEphemeral(notification)) releaseSilenced(notification, originalId)
      else writeSilenced(notification, snapshot)
      return
    }

    persistPopupFile(snapshot)
    watchForUpdates(notification, snapshot)
    Qt.callLater(function() {
      // closed before its row went in
      if (service.liveRefs[originalId] !== notification) {
        service.archivePopupFileFor(snapshot)
        return
      }
      removePopupsByOriginalId(originalId, NotificationLogic.popupFileName(snapshot))
      popupModel.insert(0, snapshot)
      service.refreshPopup(notification, originalId, snapshot.timestamp)
    })
  }

  function writeSilenced(notification, written) {
    service.materializeImage(written, function(resolved) {
      service.writeEntryFile(resolved, service.historyDir, function() {
        // a sender's CloseNotification while the write was queued leaves a destroyed object that reads as empty
        if (service.liveRefs[resolved.originalId] !== notification) return
        var updated = null
        try {
          updated = service.snapshotOf(notification, resolved.originalId, resolved.timestamp)
        } catch (e) {
        }
        // compare unresolved input, else the png re-encodes forever
        if (updated && NotificationLogic.popupRowChanged(written, updated)) {
          service.writeSilenced(notification, updated)
          return
        }
        service.releaseSilenced(notification, resolved.originalId)
      })
    })
  }

  function releaseSilenced(notification, originalId) {
    if (liveRefs[originalId] === notification) delete liveRefs[originalId]
    try {
      notification.tracked = false
    } catch (e) {
    }
  }

  readonly property var updateSignals: [
    "summaryChanged", "bodyChanged", "appNameChanged", "appIconChanged",
    "imageChanged", "urgencyChanged", "expireTimeoutChanged", "hintsChanged"
  ]

  function watchForUpdates(notification, snapshot) {
    function refresh() {
      service.refreshPopup(notification, snapshot.originalId, snapshot.timestamp)
    }

    for (let i = 0; i < updateSignals.length; i++) {
      let signal = notification[updateSignals[i]]
      if (signal && typeof signal.connect === "function") signal.connect(refresh)
    }
  }

  function rowIndexOf(originalId, timestamp) {
    for (let i = 0; i < popupModel.count; i++) {
      let row = popupModel.get(i)
      if (row && row.originalId === originalId && row.timestamp === timestamp) return i
    }
    return -1
  }

  function refreshPopup(notification, originalId, timestamp) {
    if (service.liveRefs[originalId] !== notification) return

    var updated
    try {
      updated = service.snapshotOf(notification, originalId, timestamp)
    } catch (e) {
      return
    }

    var index = rowIndexOf(originalId, timestamp)
    if (index < 0 || !NotificationLogic.popupRowChanged(popupModel.get(index), updated)) return
    NotificationLogic.POPUP_ROLES.forEach(function(role) { popupModel.setProperty(index, role, updated[role]) })
    persistPopupFile(updated)
  }

  function isRestoredRow(row) {
    return !!row && !!restoredPopups[NotificationLogic.popupFileName(row)]
  }

  function removePopupsByOriginalId(originalId, keepFileName) {
    for (let i = popupModel.count - 1; i >= 0; i--) {
      let row = popupModel.get(i)
      if (!row || row.originalId !== originalId) continue
      if (isRestoredRow(row)) continue
      if (NotificationLogic.popupFileName(row) !== keepFileName) deletePopupFileFor(row)
      popupModel.remove(i)
    }
  }

  function closePopupsByOriginalId(originalId) {
    if (service.liveRefs[originalId]) return
    for (let i = popupModel.count - 1; i >= 0; i--) {
      let row = popupModel.get(i)
      if (!row || row.originalId !== originalId || isRestoredRow(row)) continue
      archivePopupFileFor(row)
      popupModel.remove(i)
    }
  }

  // reason "replay": the row leaves the screen only, the notification stays open for its sender
  function removePopup(index, reason) {
    if (index < 0 || index >= popupModel.count) return
    var entry = popupModel.get(index)
    var restored = isRestoredRow(entry)
    var ref = !restored && entry.originalId >= 0 ? liveRefs[entry.originalId] : null
    archivePopupFileFor(entry)
    if (restored) delete restoredPopups[NotificationLogic.popupFileName(entry)]
    popupModel.remove(index)
    try {
      if (ref && ref.tracked && reason !== "replay") {
        if (reason === "expire" && typeof ref.expire === "function") ref.expire()
        else ref.dismiss()
      }
    } catch (e) {
    }
  }

  function clearPopups(reason) {
    while (popupModel.count > 0) removePopup(0, reason)
  }

  function invokeDefaultAction(entry) {
    var ref = !isRestoredRow(entry) ? liveRefs[entry.originalId] : null
    try {
      for (let i = 0; ref && ref.actions && i < ref.actions.length; i++) {
        let action = ref.actions[i]
        if (action && action.identifier === "default") {
          action.invoke()
          return true
        }
      }
    } catch (e) {
      console.warn("invoke default failed:", e)
    }
    return false
  }

  function invokePopupDefault(index) {
    if (index < 0 || index >= popupModel.count) return
    var entry = popupModel.get(index)
    var argv = NotificationLogic.parseExecArgv(entry.execArgv)
    // a browser started here must not join quickshell.service
    if (argv) Quickshell.execDetached(["uwsm-app", "--"].concat(argv))
    else if (!invokeDefaultAction(entry)) focusApp(entry)
    removePopup(index)
  }

  function focusApp(entry) {
    if (!entry.app) return
    focusAppProc.command = ["bash", "-c",
      "addr=$(hyprctl clients -j | jq -r --arg app \"$1\" " +
      "'[.[] | select((.class // \"\") | ascii_downcase | contains($app | ascii_downcase))][0].address // empty'); " +
      "[[ -n $addr ]] && hyprctl dispatch \"hl.dsp.focus({ window = 'address:$addr' })\"",
      "--", String(entry.app)]
    focusAppProc.running = true
  }

  Process { id: focusAppProc; running: false }

  property var restoredPopups: ({})
  property var fileJobs: []
  property var fileJob: null
  property int historyRevision: 0

  function enqueueFileJob(command, done) {
    fileJobs = fileJobs.concat([{ command: command, done: done || null }])
    runNextFileJob()
  }

  function runNextFileJob() {
    if (fileJob || fileJobs.length === 0) return
    fileJob = fileJobs[0]
    fileJobs = fileJobs.slice(1)
    fileJobProc.command = fileJob.command
    fileJobProc.running = true
  }

  Process {
    id: fileJobProc
    running: false
    stdout: StdioCollector { id: fileJobOut; waitForEnd: true }
    onExited: {
      var done = service.fileJob.done
      var touchedFiles = service.fileJob.command.some(function(arg) {
        return String(arg).indexOf(service.popupStateDir) === 0
      })
      service.fileJob = null
      if (touchedFiles) service.historyRevision++
      try {
        if (done) done(fileJobOut.text)
      } catch (e) {
        console.warn("notifications: file job callback failed:", e)
      }
      service.runNextFileJob()
    }
  }

  function readEntryFiles(dir, done) {
    enqueueFileJob(["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", dir], done)
  }

  readonly property string copyImagesScript:
    "while (( $# >= 2 )); do\n" +
    "  if [[ -f $1 ]] && timeout 5 head -c 5242881 -- \"$1\" > \"$2.tmp\" 2>/dev/null &&\n" +
    "     (( $(stat -c%s -- \"$2.tmp\") <= 5242880 )); then mv -f -- \"$2.tmp\" \"$2\"; else rm -f -- \"$2.tmp\"; fi\n" +
    "  shift 2\n" +
    "done\n"

  readonly property string trimScript:
    "ls -1 \"$dir\" 2>/dev/null | sort -n | head -n \"-$keep\" | while IFS= read -r stale; do rm -f \"$dir/$stale\" \"$imgs/${stale%.json}\"-*; done"

  function writeEntryFile(entry, dir, done) {
    var persistable = NotificationLogic.persistablePopup(entry, imagesDir)
    var command = ["bash", "-c",
      "dir=\"$1\" keep=\"$2\" name=\"$3\" json=\"$4\" imgs=\"$5\"\n" +
      "shift 5\n" +
      "mkdir -p \"$dir\" \"$imgs\" || exit 0\n" +
      copyImagesScript +
      "printf '%s\\n' \"$json\" > \"$dir/$name\" || exit 0\n" +
      (dir === historyDir ? trimScript : ""), "--",
      dir,
      String(historyLimit),
      NotificationLogic.popupFileName(entry),
      NotificationLogic.serializePopup(persistable.entry),
      imagesDir]
    persistable.copies.forEach(function(copy) { command.push(copy.from, copy.to) })
    enqueueFileJob(command, done)
  }

  function persistPopupFile(snapshot) {
    service.materializeImage(snapshot, function(resolved) { service.writeEntryFile(resolved, service.popupStateDir) })
  }

  function materializeImage(snapshot, done) {
    var url = String((snapshot && snapshot.image) || "")
    if (url.indexOf("image://") !== 0) {
      done(snapshot)
      return
    }

    if (!imageGrabWindow.backingWindowVisible) {
      if (service.pendingGrabs.length >= service.pendingGrabsMax) {
        done(snapshot)
        return
      }
      service.pendingGrabs.push({ snapshot: snapshot, done: done })
      return
    }

    var outPath = service.imagesDir + NotificationLogic.imageStem(snapshot) + "-materialized.png"
    var saver = imageSaverComponent.createObject(imageGrabWindow.contentItem, { source: url })
    if (!saver) {
      done(snapshot)
      return
    }

    function finish() {
      if (saver.status !== Image.Ready) {
        saver.destroy()
        done(snapshot)
        return
      }
      var grabbed = saver.grabToImage(function(grabResult) {
        var ok = false
        try {
          ok = grabResult.saveToFile(outPath)
        } catch (e) {
        }
        saver.destroy()
        done(ok ? Object.assign({}, snapshot, { image: "file://" + outPath }) : snapshot)
      })
      if (!grabbed) {
        saver.destroy()
        done(snapshot)
      }
    }

    if (saver.status === Image.Ready || saver.status === Image.Error) finish()
    else saver.statusChanged.connect(finish)
  }

  readonly property int pendingGrabsMax: 16
  property var pendingGrabs: []

  function flushPendingGrabs() {
    if (!imageGrabWindow.backingWindowVisible) return
    var queued = service.pendingGrabs
    service.pendingGrabs = []
    for (let i = 0; i < queued.length; i++)
      service.materializeImage(queued[i].snapshot, queued[i].done)
  }

  PanelWindow {
    id: imageGrabWindow

    visible: true
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    implicitWidth: 1
    implicitHeight: 1
    color: "transparent"
    anchors { top: true; left: true }
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.namespace: "quickshell-notification-image-grab"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    onBackingWindowVisibleChanged: if (backingWindowVisible) service.flushPendingGrabs()
  }

  Component {
    id: imageSaverComponent
    Image {
      visible: false
      asynchronous: true
      cache: false
    }
  }

  function deletePopupFileFor(row) {
    enqueueFileJob(["bash", "-c",
      "rm -f \"$1/$2.json\" \"$3/$2\"-*", "--",
      popupStateDir, NotificationLogic.imageStem(row), imagesDir])
  }

  function archivePopupFileFor(row) {
    enqueueFileJob(["bash", "-c",
      "dir=\"$1\" keep=\"$2\" imgs=\"$5\"\n" +
      "mkdir -p \"$dir\" && mv -f \"$4/$3\" \"$dir/$3\" 2>/dev/null || exit 0\n" +
      trimScript, "--",
      historyDir,
      String(historyLimit),
      NotificationLogic.popupFileName(row),
      popupStateDir,
      imagesDir])
  }

  function clearHistory() {
    clearPopups()
    enqueueFileJob(["bash", "-c", "dir=\"$1\" keep=0 imgs=\"$2\"\n" + trimScript, "--", historyDir, imagesDir])
  }

  // the files go before the toast, else its archive move shows the row again until the delete
  function removeEntry(originalId, timestamp) {
    var row = { originalId: originalId, timestamp: timestamp }
    enqueueFileJob(["bash", "-c",
      "rm -f \"$1/$3.json\" \"$2/$3.json\" \"$4/$3\"-*", "--",
      popupStateDir, historyDir, NotificationLogic.imageStem(row), imagesDir])
    removePopup(rowIndexOf(originalId, timestamp))
  }

  function sweepOrphanImages() {
    enqueueFileJob(["bash", "-c",
      "for img in \"$3\"/*; do\n" +
      "  [[ -e $img ]] || continue\n" +
      "  [[ $img == *.tmp ]] && { rm -f -- \"$img\"; continue; }\n" +
      "  stem=\"${img##*/}\"\n" +
      "  stem=\"${stem%-*}\"\n" +
      "  [[ -e $1/$stem.json || -e $2/$stem.json ]] || rm -f \"$img\"\n" +
      "done", "--", popupStateDir, historyDir, imagesDir])
  }

  property var replayCarryOver: []
  property bool historyReadQueued: false

  function showRecentHistory() {
    if (service.historyReadQueued) return "ok"
    service.historyReadQueued = true
    service.replayCarryOver = liveRowsForReplay()
    readEntryFiles(historyDir, replayHistory)
    return "ok"
  }

  function liveRowsForReplay() {
    var rows = []
    for (let i = 0; i < popupModel.count; i++) {
      let row = popupModel.get(i)
      if (!row || row.originalId < 0) continue
      let entry = { id: row.id, originalId: row.originalId, timestamp: row.timestamp }
      NotificationLogic.POPUP_ROLES.forEach(function(role) { entry[role] = row[role] })
      rows.push(NotificationLogic.persistablePopup(entry, imagesDir).entry)
    }
    return rows
  }

  function replayHistory(raw) {
    var rows = NotificationLogic.historyRows(raw, service.replayCarryOver, service.historyLimit)
    service.replayCarryOver = []
    service.historyReadQueued = false

    if (rows.length === 0) {
      popupModel.insert(0, NotificationLogic.historyEntry({
        id: -1,
        app: NotificationLogic.ACTION_APP,
        summary: "No recent notifications",
        glyph: "\u{f009a}",
        urgency: NotificationUrgency.Low,
        timestamp: Date.now()
      }))
      return
    }

    // live notifications ride along in the history rows (liveRowsForReplay), still open for their senders
    clearPopups("replay")
    for (let i = 0; i < rows.length; i++) {
      service.restoredPopups[NotificationLogic.popupFileName(rows[i])] = true
      popupModel.append(rows[i])
    }
  }

  function restorePopups(raw) {
    var now = Date.now()
    var live = []
    NotificationLogic.parsePopupFiles(raw).forEach(function(entry) {
      var duration = service.durationFor(entry.urgency, entry.expireTimeout)
      if (NotificationLogic.popupExpired(entry, duration, now)) {
        service.archivePopupFileFor(entry)
        return
      }
      if (duration > 0) {
        entry.deadline = now + duration
        service.persistPopupFile(entry)
        delete entry.deadline
      }
      live.push(entry)
    })

    Qt.callLater(function() {
      live.forEach(function(entry) {
        if (service.rowIndexOf(entry.originalId, entry.timestamp) >= 0) return
        service.restoredPopups[NotificationLogic.popupFileName(entry)] = true
        popupModel.append(entry)
      })
    })
  }

  Component.onCompleted: {
    enqueueFileJob(["mkdir", "-p", service.popupStateDir, service.historyDir, service.imagesDir])
    readEntryFiles(service.popupStateDir, service.restorePopups)
    sweepOrphanImages()
  }

  IpcHandler {
    target: "notifications"

    function dndState(): string {
      return service.doNotDisturb ? "on" : "off"
    }

    function toggleDnd(): string {
      service.setDoNotDisturb(!service.doNotDisturb)
      return dndState()
    }

    function setDnd(value: string): string {
      service.setDoNotDisturb(["true", "1", "on", "yes"].indexOf(String(value || "").toLowerCase()) >= 0)
      return dndState()
    }

    function isDnd(): string {
      return dndState()
    }

    function showHistory(): string {
      return service.showRecentHistory()
    }

    function clear(): string {
      service.clearHistory()
      return "ok"
    }

    function dismissAll(): string {
      service.clearPopups()
      return "ok"
    }

    function dismissOne(): string {
      if (popupModel.count === 0) return "none"
      service.removePopup(0)
      return "ok"
    }

    function invokeLast(): string {
      if (popupModel.count === 0) return "none"
      service.invokePopupDefault(0)
      return "ok"
    }

    function dismiss(summary: string): string {
      var needle = String(summary || "")
      if (!needle) return "none"
      var hit = false
      for (let i = popupModel.count - 1; i >= 0; i--) {
        if (String(popupModel.get(i).summary || "").indexOf(needle) === -1) continue
        service.removePopup(i)
        hit = true
      }
      return hit ? "ok" : "none"
    }

    function ping(): string { return "ok" }
  }

  NotificationServer {
    keepOnReload: false
    imageSupported: true
    actionsSupported: true
    bodyMarkupSupported: true
    bodyHyperlinksSupported: true
    persistenceSupported: true

    onNotification: function(notification) {
      service.handleNotification(notification)
    }
  }

  readonly property var focusedScreen: {
    var screens = Quickshell.screens
    var focused = Hyprland.focusedMonitor
    var name = focused ? String(focused.name) : ""
    if (!name && service.shell) name = String(service.shell.mainScreenName || "")
    for (let i = 0; i < screens.length; i++)
      if (String(screens[i].name) === name) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }

  property var popupScreen: null
  property int popupRevision: 0

  Connections {
    target: popupModel
    function onCountChanged() {
      service.popupRevision++
      if (popupModel.count > 0) {
        releaseTimer.stop()
        if (!service.popupScreen) service.popupScreen = service.focusedScreen
      } else {
        releaseTimer.restart()
      }
    }
  }

  Timer {
    id: releaseTimer
    interval: Style.motion.exit + 16
    onTriggered: if (popupModel.count === 0) service.popupScreen = null
  }

  function rowApp(i) {
    var row = i >= 0 && i < popupModel.count ? popupModel.get(i) : null
    return row ? String(row.app || "") : ""
  }

  function groupSizeAt(i) {
    var app = rowApp(i)
    if (!app) return 1
    if (i > 0 && rowApp(i - 1) === app) return 0
    var n = 1
    while (rowApp(i + n) === app) n++
    return n
  }

  function actionsFor(originalId, timestamp) {
    var index = rowIndexOf(originalId, timestamp)
    if (index < 0 || isRestoredRow(popupModel.get(index))) return []
    var ref = liveRefs[originalId]
    var out = []
    try {
      for (let i = 0; ref && ref.actions && i < ref.actions.length; i++) {
        let a = ref.actions[i]
        if (a && a.identifier !== "default" && String(a.text || "").length > 0
            && !NotificationLogic.isHiddenAction(a.identifier, a.text))
          out.push({ id: String(a.identifier), text: String(a.text) })
      }
    } catch (e) {
    }
    return out
  }

  function invokeAction(index, identifier) {
    if (index < 0 || index >= popupModel.count) return
    var entry = popupModel.get(index)
    var ref = !isRestoredRow(entry) ? liveRefs[entry.originalId] : null
    try {
      for (let i = 0; ref && ref.actions && i < ref.actions.length; i++) {
        if (ref.actions[i] && String(ref.actions[i].identifier) === identifier) {
          ref.actions[i].invoke()
          break
        }
      }
    } catch (e) {
      console.warn("invoke action failed:", e)
    }
    removePopup(index)
  }

  Variants {
    model: service.popupScreen ? [service.popupScreen] : []

    PanelWindow {
      required property var modelData
      screen: modelData

      // hyprland keeps no_anim on this namespace: the ListView transitions below animate each toast
      WlrLayershell.namespace: "quickshell-notifications"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"

      anchors { top: true; bottom: true; left: true; right: true }

      mask: Region { item: popupList }

      ListView {
        id: popupList
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: service.barClearance
        anchors.rightMargin: Style.gapsOut
        width: service.toastWidth
        height: Math.min(contentHeight, parent.height - service.barClearance - Style.gapsOut)
        interactive: false
        spacing: 0
        model: popupModel

        add: Transition {
          ParallelAnimation {
            NumberAnimation { property: "x"; from: service.toastWidth; to: 0; duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Style.motion.base }
          }
        }
        remove: Transition {
          ParallelAnimation {
            NumberAnimation { property: "x"; to: service.toastWidth; duration: Style.motion.exit; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.leave }
            NumberAnimation { property: "opacity"; to: 0; duration: Style.motion.exit }
          }
        }
        displaced: Transition {
          NumberAnimation { properties: "x,y"; duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
          NumberAnimation { property: "opacity"; to: 1; duration: Style.motion.fast }
        }

        delegate: Item {
          id: cardSlot
          required property int index
          required property int originalId
          required property string app
          required property string appIcon
          required property string summary
          required property string body
          required property string image
          required property string glyph
          required property int urgency
          required property double expireTimeout
          required property double timestamp

          readonly property int groupSize: { void service.popupRevision; return index >= 0 ? service.groupSizeAt(index) : 1 }
          readonly property bool folded: groupSize === 0

          width: popupList.width
          height: folded ? 0 : card.implicitHeight + Style.spacing.sm
          visible: !folded

          readonly property real lifetime: service.durationFor(cardSlot.urgency, cardSlot.expireTimeout)
          readonly property real quarterMs: cardSlot.lifetime / card.gaugeSegments
          property real remainingMs: cardSlot.lifetime
          property double resumedAtMs: Date.now()
          readonly property bool ticking: cardSlot.lifetime > 0 && !card.hovered && cardSlot.index >= 0
          readonly property int segmentsLeft: cardSlot.lifetime > 0
            ? Math.max(0, Math.ceil(cardSlot.remainingMs / cardSlot.quarterMs - 0.001)) : 0

          function restartLifetime() {
            cardSlot.remainingMs = cardSlot.lifetime
            cardSlot.resumedAtMs = Date.now()
            expiryTimer.interval = Math.max(1, cardSlot.quarterMs)
            if (cardSlot.ticking) expiryTimer.restart()
          }

          function nextStepMs() {
            var below = (cardSlot.segmentsLeft - 1) * cardSlot.quarterMs
            return Math.max(1, cardSlot.remainingMs - below)
          }

          onTickingChanged: {
            if (cardSlot.ticking) {
              cardSlot.resumedAtMs = Date.now()
              expiryTimer.interval = cardSlot.nextStepMs()
              expiryTimer.restart()
            } else {
              expiryTimer.stop()
              cardSlot.remainingMs = Math.max(1, cardSlot.remainingMs - (Date.now() - cardSlot.resumedAtMs))
            }
          }
          onLifetimeChanged: cardSlot.restartLifetime()
          onSummaryChanged: cardSlot.restartLifetime()
          onBodyChanged: cardSlot.restartLifetime()
          onImageChanged: cardSlot.restartLifetime()

          Timer {
            id: expiryTimer
            interval: cardSlot.quarterMs
            onTriggered: {
              cardSlot.remainingMs = Math.max(0, (cardSlot.segmentsLeft - 1) * cardSlot.quarterMs)
              cardSlot.resumedAtMs = Date.now()
              if (cardSlot.remainingMs <= 0) {
                if (cardSlot.index >= 0) service.removePopup(cardSlot.index, "expire")
                return
              }
              interval = cardSlot.nextStepMs()
              restart()
            }
          }

          Component.onCompleted: if (cardSlot.ticking) { expiryTimer.interval = cardSlot.nextStepMs(); expiryTimer.start() }

          NotificationCard {
            id: card
            anchors.right: parent.right
            visible: !cardSlot.folded
            app: cardSlot.app
            appIcon: cardSlot.appIcon
            summary: cardSlot.summary
            body: cardSlot.body
            image: cardSlot.image
            urgency: cardSlot.urgency
            timestamp: cardSlot.timestamp
            now: service.popupNowMs
            glyph: cardSlot.glyph
            groupCount: Math.max(1, cardSlot.groupSize)
            segmentsLeft: cardSlot.segmentsLeft
            actions: service.actionsFor(cardSlot.originalId, cardSlot.timestamp)

            onCloseRequested: if (cardSlot.index >= 0) service.removePopup(cardSlot.index)
            onCardClicked: if (cardSlot.index >= 0) service.invokePopupDefault(cardSlot.index)
            onActionInvoked: function(identifier) { if (cardSlot.index >= 0) service.invokeAction(cardSlot.index, identifier) }
          }
        }
      }
    }
  }
}
