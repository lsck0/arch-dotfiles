import QtQuick
import QtQuick.Layouts
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

  // injected by shell.qml ensureService()
  property var shell: null

  readonly property string stateDir: Paths.state + "/"
  readonly property string settingsPath: stateDir + "notifications.json"
  readonly property string popupStateDir: stateDir + "notifications/"
  readonly property string historyDir: popupStateDir + "history/"
  readonly property string imagesDir: popupStateDir + "images/"
  readonly property int barClearance: Style.bar.sizeHorizontal + Style.gapsOut

  // kept out of the model: stale qobject roles segfault
  property var liveRefs: ({})

  PersistentProperties {
    id: persisted
    reloadableId: "quickshell-notifications"
    property bool doNotDisturb: false
    onDoNotDisturbChanged: {
      if (service._hydrating) return
      service.scheduleSettingsSave()
    }
  }

  property bool _hydrating: false

  readonly property alias doNotDisturb: persisted.doNotDisturb

  function setDoNotDisturb(value) {
    persisted.doNotDisturb = !!value
  }

  ListModel { id: popupModel }

  readonly property int historyLimit: 10

  property double popupNowMs: Date.now()
  Timer {
    interval: 20000
    running: popupModel.count > 0
    repeat: true
    triggeredOnStart: true
    onTriggered: service.popupNowMs = Date.now()
  }

  readonly property int lowPopupDuration: 5000
  readonly property int normalPopupDuration: 8000
  readonly property int maxPopupDuration: 30000

  function durationFor(urgency, expireTimeout) {
    switch (urgency) {
    case NotificationUrgency.Critical:
      return 0
    case NotificationUrgency.Low:
      return Math.min(maxPopupDuration, Math.max(lowPopupDuration, requestedDuration(expireTimeout)))
    default:
      return Math.min(maxPopupDuration, Math.max(normalPopupDuration, requestedDuration(expireTimeout)))
    }
  }

  function requestedDuration(expireTimeout) {
    var ms = Number(expireTimeout || 0)
    if (!isFinite(ms) || ms <= 0) return 0
    return Math.round(ms)
  }

  function shouldBypassDnd(notification) {
    return NotificationLogic.shouldBypassDnd(notification, NotificationUrgency.Critical)
  }

  function snapshotOf(notification) {
    return NotificationLogic.snapshotOf(notification, Date.now())
  }

  function isEphemeral(notification) {
    var transient = false
    try {
      transient = !!(notification.hints && notification.hints["transient"])
    } catch (e) { transient = false }
    return transient || NotificationLogic.isEphemeralApp(String(notification.appName || ""))
  }

  function handleNotification(notification) {
    notification.tracked = true
    var snapshot = snapshotOf(notification)
    liveRefs[snapshot.originalId] = notification
    notification.closed.connect(function() {
      if (service.liveRefs[snapshot.originalId] === notification)
        delete service.liveRefs[snapshot.originalId]
    })

    if (service.doNotDisturb && !shouldBypassDnd(notification)) {
      if (!isEphemeral(notification)) {
        writeSilenced(notification, snapshot)
        return
      }
      delete liveRefs[snapshot.originalId]
      notification.tracked = false
      return
    }

    persistPopupFile(snapshot)
    watchForUpdates(notification, snapshot)
    Qt.callLater(function() {
      removePopupsByOriginalId(snapshot.originalId, NotificationLogic.popupFileName(snapshot))
      popupModel.insert(0, snapshot)
      service.refreshPopup(notification, snapshot.originalId, snapshot.timestamp)
    })
  }

  function writeSilenced(notification, written) {
    service.materializeImage(written, function(resolved) {
      service.writeHistoryFile(resolved, function() {
        var updated = null
        try {
          updated = NotificationLogic.replacementSnapshot(notification, resolved.originalId, resolved.timestamp)
        } catch (e) {
          // torn down while the write was queued
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

    for (var i = 0; i < updateSignals.length; i++) {
      var signal = notification[updateSignals[i]]
      if (signal && typeof signal.connect === "function") signal.connect(refresh)
    }
  }

  function refreshPopup(notification, originalId, timestamp) {
    if (service.liveRefs[originalId] !== notification) return

    var updated
    try {
      updated = NotificationLogic.replacementSnapshot(notification, originalId, timestamp)
    } catch (e) {
      return
    }

    var roles = NotificationLogic.popupRoles()
    for (var i = 0; i < popupModel.count; i++) {
      var row = popupModel.get(i)
      if (!row || row.originalId !== originalId || row.timestamp !== timestamp) continue
      if (!NotificationLogic.popupRowChanged(row, updated)) return
      for (var r = 0; r < roles.length; r++) popupModel.setProperty(i, roles[r], updated[roles[r]])
      persistPopupFile(updated)
      return
    }
  }

  function isRestoredRow(row) {
    return !!row && !!restoredPopups[NotificationLogic.popupFileName(row)]
  }

  function removePopupsByOriginalId(originalId, keepFileName) {
    for (var i = popupModel.count - 1; i >= 0; i--) {
      var row = popupModel.get(i)
      if (!row || row.originalId !== originalId) continue
      if (isRestoredRow(row)) continue
      if (NotificationLogic.popupFileName(row) !== keepFileName) deletePopupFileFor(row)
      popupModel.remove(i)
    }
  }

  function dismissPopup(index) {
    removePopup(index, "dismiss")
  }

  function expirePopup(index) {
    removePopup(index, "expire")
  }

  function removePopup(index, reason) {
    if (index < 0 || index >= popupModel.count) return
    var entry = popupModel.get(index)
    var originalId = entry ? entry.originalId : -1
    var restored = isRestoredRow(entry)
    var ref = !restored && originalId >= 0 ? liveRefs[originalId] : null
    if (entry) {
      archivePopupFileFor(entry)
      if (restored) delete restoredPopups[NotificationLogic.popupFileName(entry)]
    }
    popupModel.remove(index)
    if (ref) {
      try {
        if (ref.tracked) {
          if (reason === "expire" && typeof ref.expire === "function") ref.expire()
          else ref.dismiss()
        }
      } catch (e) {
      }
    }
  }

  function clearPopups() {
    while (popupModel.count > 0) dismissPopup(0)
  }

  function invokePopupDefault(index) {
    if (index < 0 || index >= popupModel.count) return
    var entry = popupModel.get(index)

    var argv = NotificationLogic.parseExecArgv(entry ? entry.execArgv : "")
    if (argv) {
      Quickshell.execDetached(argv)
      dismissPopup(index)
      return
    }
    var ref = entry && !isRestoredRow(entry) ? liveRefs[entry.originalId] : null
    var invoked = false
    try {
      if (ref && ref.actions) {
        for (var i = 0; i < ref.actions.length; i++) {
          var action = ref.actions[i]
          if (action && action.identifier === "default") {
            action.invoke()
            invoked = true
            break
          }
        }
      }
    } catch (e) {
      console.warn("invoke default failed:", e)
    }
    if (!invoked) focusApp(entry)
    dismissPopup(index)
  }

  function focusApp(entry) {
    if (!entry || !entry.app) return
    focusAppProc.command = ["bash", "-c",
      "addr=$(hyprctl clients -j | jq -r --arg app \"$1\" " +
      "'[.[] | select((.class // \"\") | ascii_downcase | contains($app | ascii_downcase))][0].address // empty'); " +
      "[[ -n $addr ]] && hyprctl dispatch \"hl.dsp.focus({ window = 'address:$addr' })\"",
      "--", String(entry.app)]
    focusAppProc.running = true
  }

  Process { id: focusAppProc; running: false }

  Process {
    id: ensureDirsProc
    command: ["mkdir", "-p", service.stateDir, service.popupStateDir, service.historyDir, service.imagesDir]
    running: false
  }

  property var restoredPopups: ({})
  property var popupFileQueue: []
  property var runningPopupFileJobDone: null

  function enqueuePopupFileJob(command, done) {
    popupFileQueue = popupFileQueue.concat([{ command: command, done: done || null }])
    runNextPopupFileJob()
  }

  function enqueueHistoryRead() {
    popupFileQueue = popupFileQueue.concat([{ read: true }])
    runNextPopupFileJob()
  }

  function runNextPopupFileJob() {
    if (readHistoryProc.running || popupFileProc.running) return
    if (popupFileQueue.length === 0) return

    var job = popupFileQueue[0]
    popupFileQueue = popupFileQueue.slice(1)

    if (job.read) {
      startHistoryRead()
      return
    }

    popupFileProc.command = job.command
    service.runningPopupFileJobDone = job.done || null
    popupFileProc.running = true
  }

  Process {
    id: popupFileProc
    running: false
    onExited: {
      var done = service.runningPopupFileJobDone
      service.runningPopupFileJobDone = null
      if (done) {
        try {
          done()
        } catch (e) {
          console.warn("notifications: file job callback failed:", e)
        }
      }
      service.runNextPopupFileJob()
    }
  }

  readonly property string copyImagesScript:
    "while (( $# >= 2 )); do\n" +
    "  if [[ -f $1 ]] && timeout 5 head -c 5242881 -- \"$1\" > \"$2.tmp\" 2>/dev/null &&\n" +
    "     (( $(stat -c%s -- \"$2.tmp\") <= 5242880 )); then mv -f -- \"$2.tmp\" \"$2\"; else rm -f -- \"$2.tmp\"; fi\n" +
    "  shift 2\n" +
    "done\n"

  function persistPopupFile(snapshot) {
    service.materializeImage(snapshot, function(resolved) {
      var persistable = NotificationLogic.persistablePopup(resolved, imagesDir)
      var command = ["bash", "-c",
        "mkdir -p \"$1\" \"$2\" || exit 0\n" +
        "dir=\"$1\" json=\"$3\" name=\"$4\"\n" +
        "shift 4\n" +
        copyImagesScript +
        "printf '%s\\n' \"$json\" > \"$dir/$name\"", "--",
        popupStateDir,
        imagesDir,
        NotificationLogic.serializePopup(persistable.entry, NotificationUrgency.Normal),
        NotificationLogic.popupFileName(resolved)]
      for (var i = 0; i < persistable.copies.length; i++)
        command.push(persistable.copies[i].from, persistable.copies[i].to)
      enqueuePopupFileJob(command)
    })
  }

  // image-data hints are in-process image:// urls, save them to disk
  function materializeImage(snapshot, done) {
    var url = String((snapshot && snapshot.image) || "")
    if (url.indexOf("image://") !== 0) {
      done(snapshot)
      return
    }

    // grab surface not mapped yet
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
          ok = false
        }
        saver.destroy()
        if (ok) {
          var copy = {}
          for (var k in snapshot) copy[k] = snapshot[k]
          copy.image = "file://" + outPath
          done(copy)
        } else {
          done(snapshot)
        }
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
    for (var i = 0; i < queued.length; i++)
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
    if (!row) return
    enqueuePopupFileJob(["bash", "-c",
      "rm -f \"$1/$2.json\" \"$3/$2\"-*", "--",
      popupStateDir, NotificationLogic.imageStem(row), imagesDir])
  }

  readonly property string trimHistoryScript:
    "ls -1 \"$hist\" 2>/dev/null | sort -n | head -n \"-$limit\" | while IFS= read -r stale; do rm -f \"$hist/$stale\" \"$imgs/${stale%.json}\"-*; done"

  function archivePopupFileFor(row) {
    if (!row) return
    enqueuePopupFileJob(["bash", "-c",
      "mkdir -p \"$1\" || exit 0\n" +
      "hist=\"$1\" limit=\"$2\" imgs=\"$5\"\n" +
      "mv -f \"$4/$3\" \"$1/$3\" 2>/dev/null || exit 0\n" +
      trimHistoryScript, "--",
      historyDir,
      String(historyLimit),
      NotificationLogic.popupFileName(row),
      popupStateDir,
      imagesDir])
  }

  function writeHistoryFile(entry, done) {
    if (!entry) {
      if (done) done()
      return
    }
    var persistable = NotificationLogic.persistablePopup(entry, imagesDir)
    var command = ["bash", "-c",
      "mkdir -p \"$1\" \"$5\" || exit 0\n" +
      "hist=\"$1\" limit=\"$2\" name=\"$3\" json=\"$4\" imgs=\"$5\"\n" +
      "shift 5\n" +
      copyImagesScript +
      "printf '%s\\n' \"$json\" > \"$hist/$name\" || exit 0\n" +
      trimHistoryScript, "--",
      historyDir,
      String(historyLimit),
      NotificationLogic.popupFileName(entry),
      NotificationLogic.serializePopup(persistable.entry, NotificationUrgency.Normal),
      imagesDir]
    for (var i = 0; i < persistable.copies.length; i++)
      command.push(persistable.copies[i].from, persistable.copies[i].to)
    enqueuePopupFileJob(command, done)
  }

  function clearHistory() {
    enqueuePopupFileJob(["bash", "-c",
      "for f in \"$1\"/*.json; do\n" +
      "  [[ -e $f ]] || continue\n" +
      "  stale=\"${f##*/}\"\n" +
      "  rm -f \"$f\" \"$2/${stale%.json}\"-*\n" +
      "done", "--", historyDir, imagesDir])
  }

  function sweepOrphanImages() {
    enqueuePopupFileJob(["bash", "-c",
      "for img in \"$3\"/*; do\n" +
      "  [[ -e $img ]] || continue\n" +
      "  [[ $img == *.tmp ]] && { rm -f -- \"$img\"; continue; }\n" +
      "  stem=\"${img##*/}\"\n" +
      "  stem=\"${stem%-*}\"\n" +
      "  [[ -e $1/$stem.json || -e $2/$stem.json ]] || rm -f \"$img\"\n" +
      "done", "--", popupStateDir, historyDir, imagesDir])
  }

  Process {
    id: readHistoryProc
    running: false
    onExited: service.runNextPopupFileJob()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.replayHistory(text)
    }
  }

  property var replayCarryOver: []
  property bool historyReadQueued: false

  function showRecentHistory() {
    if (readHistoryProc.running || service.historyReadQueued) return "ok"
    service.replayCarryOver = liveRowsForReplay()
    service.historyReadQueued = true
    enqueueHistoryRead()
    return "ok"
  }

  function startHistoryRead() {
    service.historyReadQueued = false
    readHistoryProc.command = ["bash", "-c",
      "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", historyDir]
    readHistoryProc.running = true
  }

  function liveRowsForReplay() {
    var rows = []
    for (var i = 0; i < popupModel.count; i++) {
      var row = popupModel.get(i)
      if (!row || row.originalId < 0) continue
      rows.push(NotificationLogic.persistablePopup({
        id: row.id,
        originalId: row.originalId,
        app: row.app,
        appIcon: row.appIcon,
        summary: row.summary,
        body: row.body,
        image: row.image,
        glyph: row.glyph || "",
        execArgv: row.execArgv || "",
        urgency: row.urgency,
        timestamp: row.timestamp
      }, imagesDir).entry)
    }
    return rows
  }

  function replayHistory(raw) {
    var rows = NotificationLogic.historyRows(
      raw, service.replayCarryOver, NotificationUrgency.Normal, service.historyLimit)
    service.replayCarryOver = []

    if (rows.length === 0) {
      popupModel.insert(0, {
        id: -1,
        originalId: -1,
        app: "omarchy-action",
        appIcon: "",
        summary: "No recent notifications",
        body: "",
        image: "",
        glyph: "\u{f009a}",
        execArgv: "",
        urgency: NotificationUrgency.Low,
        expireTimeout: 0,
        timestamp: Date.now()
      })
      return
    }

    clearPopups()
    for (var i = 0; i < rows.length; i++) {
      service.restoredPopups[NotificationLogic.popupFileName(rows[i])] = true
      popupModel.append(rows[i])
    }
  }

  Process {
    id: restorePopupsProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.restorePopups(text)
    }
  }

  function restorePopups(raw) {
    var entries = NotificationLogic.parsePopupFiles(raw, NotificationUrgency.Normal)
    var now = Date.now()
    var live = []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      var duration = durationFor(entry.urgency, entry.expireTimeout)
      if (NotificationLogic.popupExpired(entry, duration, now)) {
        archivePopupFileFor(entry)
        continue
      }
      if (duration > 0) {
        entry.deadline = now + duration
        persistPopupFile(entry)
        delete entry.deadline
      }
      live.push(entry)
    }
    if (live.length === 0) return

    Qt.callLater(function() {
      for (var j = 0; j < live.length; j++) {
        var restored = live[j]
        var duplicate = false
        for (var k = 0; k < popupModel.count; k++) {
          var row = popupModel.get(k)
          if (row && row.originalId === restored.originalId && row.timestamp === restored.timestamp) {
            duplicate = true
            break
          }
        }
        if (duplicate) continue
        service.restoredPopups[NotificationLogic.popupFileName(restored)] = true
        popupModel.append(restored)
      }
    })
  }

  FileView {
    id: settingsFile
    path: service.settingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadSettings(text())
    onLoadFailed: service.loadSettings("")
  }

  Timer {
    id: settingsSaveTimer
    interval: 200
    repeat: false
    onTriggered: service.flushSettings()
  }

  function scheduleSettingsSave() {
    if (!service.settingsLoaded) return
    settingsSaveTimer.restart()
  }

  property bool settingsLoaded: false

  function loadSettings(raw) {
    if (service.settingsLoaded) return

    var parsed = NotificationLogic.parseSettings(raw)
    if (parsed.error) console.warn("notifications: settings parse failed:", parsed.errorMessage || "")

    if (parsed.dnd !== null) {
      service._hydrating = true
      persisted.doNotDisturb = parsed.dnd
      service._hydrating = false
    }

    service.settingsLoaded = true
  }

  function flushSettings() {
    settingsFile.setText(JSON.stringify({ version: 3, dnd: persisted.doNotDisturb }, null, 2) + "\n")
  }

  Component.onCompleted: {
    ensureDirsProc.running = true
    Qt.callLater(function() {
      settingsFile.reload()
      restorePopupsProc.command = ["bash", "-c",
        "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", service.popupStateDir]
      restorePopupsProc.running = true
      service.sweepOrphanImages()
    })
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
      var v = String(value || "").toLowerCase()
      var on = v === "true" || v === "1" || v === "on" || v === "yes"
      service.setDoNotDisturb(on)
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
      service.dismissPopup(0)
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
      for (var i = popupModel.count - 1; i >= 0; i--) {
        var row = popupModel.get(i)
        if (row && String(row.summary || "").indexOf(needle) !== -1) {
          service.dismissPopup(i)
          hit = true
        }
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
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name) === name) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }

  // pinned while toasts are up so they do not jump outputs
  property var popupScreen: null

  Connections {
    target: popupModel
    function onCountChanged() {
      if (popupModel.count === 0) service.popupScreen = null
      else if (!service.popupScreen) service.popupScreen = service.focusedScreen
    }
  }

  Variants {
    model: service.popupScreen ? [service.popupScreen] : []

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: popupModel.count > 0

      WlrLayershell.namespace: "quickshell-notifications"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"

      anchors { top: true; bottom: true; left: true; right: true }

      mask: Region { item: popupColumn }

      ColumnLayout {
        id: popupColumn
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: service.barClearance
        anchors.rightMargin: Style.gapsOut
        spacing: Style.space(8)

        Repeater {
          model: popupModel

          delegate: Item {
            id: cardSlot
            required property int index
            required property string app
            required property string appIcon
            required property string summary
            required property string body
            required property string image
            required property string glyph
            required property int urgency
            required property double expireTimeout
            required property double timestamp

            Layout.preferredWidth: card.implicitWidth
            Layout.alignment: Qt.AlignRight
            implicitHeight: card.implicitHeight

            readonly property real lifetime: service.durationFor(cardSlot.urgency, cardSlot.expireTimeout)
            // hover pauses the countdown, leaving resumes the remainder
            property real remainingMs: cardSlot.lifetime
            property double resumedAtMs: Date.now()
            readonly property bool ticking: cardSlot.lifetime > 0 && !card.hovered

            function restartLifetime() {
              cardSlot.remainingMs = cardSlot.lifetime
              cardSlot.resumedAtMs = Date.now()
              if (cardSlot.ticking) expiryTimer.restart()
            }

            onTickingChanged: {
              if (cardSlot.ticking) cardSlot.resumedAtMs = Date.now()
              else cardSlot.remainingMs = Math.max(0, cardSlot.remainingMs - (Date.now() - cardSlot.resumedAtMs))
            }
            onLifetimeChanged: cardSlot.restartLifetime()
            onSummaryChanged: cardSlot.restartLifetime()
            onBodyChanged: cardSlot.restartLifetime()
            onImageChanged: cardSlot.restartLifetime()

            Timer {
              id: expiryTimer
              interval: Math.max(1, cardSlot.remainingMs)
              running: cardSlot.ticking
              onTriggered: service.expirePopup(cardSlot.index)
            }

            NotificationCard {
              id: card
              anchors.right: parent.right
              app: cardSlot.app
              appIcon: cardSlot.appIcon
              summary: cardSlot.summary
              body: cardSlot.body
              image: cardSlot.image
              urgency: cardSlot.urgency
              timestamp: cardSlot.timestamp
              now: service.popupNowMs
              glyph: cardSlot.glyph

              onCloseRequested: service.dismissPopup(cardSlot.index)
              onCardClicked: service.invokePopupDefault(cardSlot.index)
            }
          }
        }
      }
    }
  }
}
