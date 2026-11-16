pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory

Item {
  id: root

  readonly property string pluginDir: Paths.plugin("clipboard")
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool clearConfirmOpen: false
  property var history: []

  // OpenPGP on the selected entry (gpg.nu); the plaintext lives only in gpgResult until close
  property string gpgMode: ""
  property var gpgKeys: []
  property var gpgPicked: ({})
  property int gpgKeyIndex: 0
  property var gpgResult: null
  property string gpgError: ""
  property string gpgText: ""
  // a picked key nobody certified needs a second ENTER: gpg then encrypts to it with --trust-model always
  property bool gpgUnverifiedArmed: false
  // every reset bumps the serial: a gpg run that finishes after the window closed or was reset is dropped
  property int gpgSerial: 0
  property int gpgRunSerial: -1
  // a gpg run longer than a moment likely waits on pinentry or a key touch: the overlay unmaps so that window shows
  property bool gpgHidden: false
  readonly property bool gpgBusy: gpgKeysProc.running || gpgEncryptProc.running || gpgDecryptProc.running
  readonly property string gpgHelper: root.pluginDir + "/gpg.nu"

  readonly property string historyPath: Paths.runtime + "/clipboard-history.json"
  readonly property string imagesDir: Paths.runtime + "/clipboard-images"
  readonly property int historyLimit: 500
  readonly property int displayLimit: 50
  readonly property string configPath: Paths.home + "/.config/quickshell/clipboard.json"
  readonly property int msPerHour: 3600000
  // fallback only; link always writes clipboard.json from clipboard_history_max_age_h in mod.nu
  readonly property int maxAgeHoursDefault: 12
  property int maxAgeMs: maxAgeHoursDefault * msPerHour
  onMaxAgeMsChanged: root.expireHistory()
  // the startup sweep waits so the current-clipboard capture can land in history first
  readonly property int imageSweepDelayMs: 3000
  property bool imagesSwept: false

  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int rowHeight: Style.space(44)

  function open() {
    panel.screen = Util.focusedScreen()
    root.gpgReset()
    root.expireHistory()
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    pointerGate.reset()
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.cancelClearHistory()
    root.gpgReset()
    root.opened = false
  }

  function gpgReset() {
    root.gpgSerial++
    gpgKeysProc.running = false
    gpgEncryptProc.running = false
    gpgDecryptProc.running = false
    root.gpgHidden = false
    root.gpgMode = ""
    root.gpgKeys = []
    root.gpgPicked = {}
    root.gpgResult = null
    root.gpgError = ""
    root.gpgText = ""
    root.gpgUnverifiedArmed = false
  }

  function rowAt(index) { return index >= 0 && index < displayModel.count ? displayModel.get(index) : null }

  function selectedEntryText() {
    var row = root.rowAt(root.selectedIndex)
    return row && row.entryType === "text" ? row.fullText : ""
  }

  function gpgCurrent() { return root.opened && root.gpgRunSerial === root.gpgSerial }

  // release the keyboard and unmap while gpg runs, so pinentry is not drawn under the card
  function gpgRun(proc, argv, text) {
    if (root.gpgBusy) return
    root.gpgError = ""
    root.gpgRunSerial = root.gpgSerial
    proc.command = argv
    proc.process.stdinEnabled = true
    proc.run()
    proc.process.write(text)
    proc.process.stdinEnabled = false
  }

  function startEncrypt() {
    var text = root.selectedEntryText()
    if (!text || root.gpgBusy) return
    root.gpgReset()
    root.gpgText = text
    root.gpgMode = "encrypt"
    root.gpgRunSerial = root.gpgSerial
    gpgKeysProc.run()
  }

  function startDecrypt() {
    var text = root.selectedEntryText()
    if (!text) return
    root.gpgReset()
    root.gpgMode = "decrypt"
    root.gpgRun(gpgDecryptProc, [root.gpgHelper, "decrypt"], text)
  }

  function gpgToggleKey(index) {
    if (index < 0 || index >= root.gpgKeys.length) return
    var picked = Object.assign({}, root.gpgPicked)
    var fpr = root.gpgKeys[index].fpr
    if (picked[fpr]) delete picked[fpr]
    else picked[fpr] = true
    root.gpgPicked = picked
    root.gpgUnverifiedArmed = false
  }

  function encryptPicked() {
    var to = Object.keys(root.gpgPicked)
    if (to.length === 0) { root.gpgError = "pick at least one recipient (space)"; return }
    var unverified = root.gpgKeys.filter(function (k) { return root.gpgPicked[k.fpr] && !k.valid })
    if (unverified.length > 0 && !root.gpgUnverifiedArmed) {
      root.gpgUnverifiedArmed = true
      root.gpgError = "not certified: " + unverified.map(function (k) { return k.uid }).join(", ")
        + "; check the fingerprint, ENTER again encrypts to it anyway"
      return
    }
    var flags = unverified.length > 0 ? ["--trust-unverified"] : []
    root.gpgRun(gpgEncryptProc, [root.gpgHelper, "encrypt"].concat(flags).concat(to), root.gpgText)
  }

  function gpgKey(event) {
    if (event.key === Qt.Key_Escape) { root.gpgReset(); return true }
    if (root.gpgMode === "decrypt") {
      const step = event.key === Qt.Key_Up ? -Style.row.list : event.key === Qt.Key_Down ? Style.row.list
        : event.key === Qt.Key_PageUp ? -plainFlick.height : event.key === Qt.Key_PageDown ? plainFlick.height : 0
      plainFlick.contentY = Math.max(0, Math.min(plainFlick.contentY + step, plainFlick.contentHeight - plainFlick.height))
      return true
    }
    if (root.gpgMode !== "encrypt" || root.gpgBusy) return true
    var n = root.gpgKeys.length
    if (event.key === Qt.Key_Up && n > 0) root.gpgKeyIndex = (root.gpgKeyIndex - 1 + n) % n
    else if (event.key === Qt.Key_Down && n > 0) root.gpgKeyIndex = (root.gpgKeyIndex + 1) % n
    else if (event.key === Qt.Key_Space) root.gpgToggleKey(root.gpgKeyIndex)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.encryptPicked()
    return true
  }

  function signatureLine(sig) {
    if (!sig) return ""
    var who = (sig.signer || "") + (sig.fpr ? "\n" + sig.fpr : "")
    switch (sig.state) {
      case "good": return "GOOD SIGNATURE\n" + who
      case "untrusted": return "SIGNED BY AN UNCERTIFIED KEY, the name may be anyone's\n" + who
      case "bad": return "BAD SIGNATURE, the message was altered or the signature is forged\n" + who
      case "expired": return "EXPIRED SIGNATURE OR KEY\n" + who
      case "revoked": return "SIGNED BY A REVOKED KEY\n" + who
      case "unverified": return "UNVERIFIED SIGNATURE, missing key or unsupported algorithm\n" + who
      default: return "NOT SIGNED"
    }
  }

  function signatureColor(sig) {
    if (!sig) return Colors.menu.text
    if (sig.state === "good") return Colors.okText
    if (sig.state === "untrusted" || sig.state === "expired") return Colors.warnText
    if (sig.state === "none") return Colors.menu.text
    return Colors.urgentText
  }

  function toggle() { root.opened ? root.close() : root.open() }

  function loadHistory(raw) {
    const loaded = ClipboardHistory.parseHistory(raw)
    const stamped = ClipboardHistory.stampUnstamped(loaded, Date.now())
    root.history = loaded
    if (stamped) root.saveHistory()
    if (root.opened) root.rebuildDisplay()
    root.expireHistory()
  }

  // drops entries past the age limit and arms the timer for the next one, so a copied secret leaves the list and
  // its tmpfs file without anyone opening the panel
  function expireHistory() {
    const now = Date.now()
    const kept = ClipboardHistory.expireEntries(root.history, now, root.maxAgeMs)
    if (kept.length !== root.history.length) root.replaceHistory(kept)
    const due = ClipboardHistory.expiryDueMs(root.history, now, root.maxAgeMs)
    if (due < 0) { expiryTimer.stop(); return }
    // the timer's clock stops in suspend, the stamps are wall clock: look again within ten minutes
    expiryTimer.interval = Math.max(expiryTimer.intervalMinMs, Math.min(due, 600000))
    expiryTimer.restart()
  }

  function saveHistory() {
    historyFile.setText(JSON.stringify(root.history.slice(0, root.historyLimit), null, 2) + "\n")
  }

  // the history limit and the age limit can push an image out
  function replaceHistory(next) {
    const before = root.imagePaths()
    root.history = next
    root.saveHistory()
    for (let i = 0; i < before.length; i++) root.dropImageFile(before[i])
    if (root.opened) root.rebuildDisplay()
  }

  function addClipboardJson(line) {
    var normalized = ClipboardHistory.parseEntryJson(line)
    if (!normalized) return
    root.replaceHistory(ClipboardHistory.addEntry(root.history, normalized, root.historyLimit, Date.now()))
    root.expireHistory()
  }

  function requestClearHistory() {
    if (root.history.length === 0) return
    root.clearConfirmOpen = true
  }

  function cancelClearHistory() {
    root.clearConfirmOpen = false
  }

  function imagePaths() {
    const seen = {}
    const paths = []
    for (let i = 0; i < root.history.length; i++) {
      const entry = root.history[i]
      if (entry.type === "image" && entry.path && !seen[entry.path]) {
        seen[entry.path] = true
        paths.push(entry.path)
      }
    }
    return paths
  }

  // an image file is shared only by identical captures (same sha256 path), so a dropped entry orphans its file
  function dropImageFile(path) {
    if (!path || root.imagePaths().indexOf(path) >= 0) return
    Quickshell.execDetached(["rm", "-f", "--", path])
  }

  function sweepImageFiles() {
    Quickshell.execDetached(["bash", "-c",
      'dir=$1; shift; shopt -s nullglob; declare -A keep; for p in "$@"; do keep[$p]=1; done; for f in "$dir"/*; do [ -n "${keep[$f]:-}" ] || rm -f -- "$f"; done',
      "clipboard-sweep", root.imagesDir].concat(root.imagePaths()))
  }

  function confirmClearHistory() {
    root.replaceHistory([])
    root.cursorActive = false
    root.cancelClearHistory()
  }

  function removeDisplayIndex(index) {
    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    var imagePath = row.entryType === "image" ? row.path : ""
    root.history = ClipboardHistory.removeEntryAt(root.history, row.historyIndex)
    root.saveHistory()
    root.dropImageFile(imagePath)

    if (displayModel.count <= 1) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count - 1) {
      root.selectedIndex = displayModel.count - 2
    }

    pointerGate.reset()
    root.rebuildDisplay()
  }

  function forgetTextHash(hash) {
    var next = root.history.filter(function(entry) { return entry.type !== "text" || Qt.md5(entry.text) !== hash })
    if (next.length !== root.history.length) root.replaceHistory(next)
  }

  function rebuildDisplay() {
    var rows = ClipboardHistory.displayRows(root.history, root.filterText, root.displayLimit)

    displayModel.clear()
    for (let i = 0; i < rows.length; i++) {
      let row = rows[i]
      displayModel.append({
        entryType: row.entryType,
        fullText: row.fullText,
        copyText: row.copyText,
        paneText: row.paneText,
        previewText: row.previewText,
        previewImage: row.previewImage ? Util.fileUrl(row.previewImage) : "",
        path: row.path,
        mime: row.mime,
        historyIndex: row.index
      })
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function select(delta) {
    if (displayModel.count === 0) return
    pointerGate.reset()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      // sign-safe wrap: a PageUp step larger than the list (short history) made JS % return a negative index, losing the selection
      selectedIndex = ((selectedIndex + delta) % displayModel.count + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    pointerGate.reset()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    root.cursorActive = true
    pointerGate.reset()
    root.rebuildDisplay()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function copyText(text, mime) {
    if (copyTextProc.running) return
    copyTextProc.command = mime ? ["wl-copy", "--type", mime] : ["wl-copy"]
    copyTextProc.stdinEnabled = true
    copyTextProc.running = true
    copyTextProc.write(text)
    copyTextProc.stdinEnabled = false
  }

  function copyRow(row, paste) {
    if (!row) return
    root.close()
    if (row.entryType === "image") {
      Quickshell.execDetached(["bash", "-c", "wl-copy --type " + Util.shellQuote(row.mime) + " < " + Util.shellQuote(row.path)])
    } else if (row.copyText) {
      root.copyText(row.copyText, row.entryType === "file" ? row.mime : "")
    }
    if (paste) Quickshell.execDetached([root.pluginDir + "/paste.nu"])
  }

  Process {
    id: copyTextProc
    command: ["wl-copy"]
  }

  JsonProcess {
    id: gpgKeysProc
    command: [root.gpgHelper, "keys"]
    onParsed: function (data) {
      if (!root.gpgCurrent()) return
      root.gpgKeys = data.keys || []
      var picked = {}
      if (data.signer) picked[data.signer] = true
      root.gpgPicked = picked
      var own = root.gpgKeys.findIndex(function (k) { return k.fpr === data.signer })
      root.gpgKeyIndex = Math.max(0, own)
      if (root.gpgKeys.length === 0) root.gpgError = "no key to encrypt to"
    }
    onFailed: function (error) { if (root.gpgCurrent()) root.gpgError = "gpg keys: " + error }
  }

  // the armored message replaces the plaintext: onto the clipboard, the plaintext's history entry forgotten
  JsonProcess {
    id: gpgEncryptProc
    onParsed: function (data) {
      if (!root.gpgCurrent()) return
      root.gpgHidden = false
      if (!data.ok) { root.gpgError = data.error; return }
      var plain = root.gpgText
      root.close()
      root.copyText(data.armored + "\n")
      root.forgetTextHash(Qt.md5(plain))
      Quickshell.execDetached(["notify-send", "--app-name=clipboard", "Encrypted and signed", "The armored message is on the clipboard"])
    }
    onFailed: function (error) { if (root.gpgCurrent()) { root.gpgHidden = false; root.gpgError = "gpg encrypt: " + error } }
  }

  JsonProcess {
    id: gpgDecryptProc
    // gpg.nu answers one JSON line: parsed per line, no collector keeps the plaintext after the window closes
    streaming: true
    onParsed: function (data) {
      if (!root.gpgCurrent()) return
      root.gpgHidden = false
      if (!data.ok) { root.gpgError = data.error; return }
      root.gpgResult = { plaintext: String(data.plaintext || "").replace(/\n+$/, ""), signature: data.signature }
    }
    onFailed: function (error) { if (root.gpgCurrent()) { root.gpgHidden = false; root.gpgError = "gpg decrypt: " + error } }
  }

  function openRow(row) {
    if (!row) return
    root.close()
    Quickshell.execDetached(["uwsm-app", "--", "xdg-open", row.path || row.fullText])
  }

  Timer {
    interval: 600
    running: gpgEncryptProc.running || gpgDecryptProc.running
    onTriggered: {
      root.gpgHidden = true
      Quickshell.execDetached(["notify-send", "--app-name=clipboard", "Waiting for gpg", "pinentry or a key touch; the clipboard window comes back after"])
    }
  }

  // back from a pinentry: the card maps again and takes the keyboard
  onGpgHiddenChanged: if (!root.gpgHidden && root.opened) Qt.callLater(function() { keyCatcher.forceActiveFocus() })

  Component.onCompleted: initProc.running = true

  Timer {
    id: imageSweepTimer
    interval: root.imageSweepDelayMs
    onTriggered: root.sweepImageFiles()
  }

  Timer {
    id: expiryTimer
    readonly property int intervalMinMs: 1000
    onTriggered: root.expireHistory()
  }

  WatchedFile {
    path: root.configPath
    onLoaded: {
      var hours = 0
      try { hours = Number(JSON.parse(text()).max_age_h) } catch (e) {}
      root.maxAgeMs = (hours > 0 ? hours : root.maxAgeHoursDefault) * root.msPerHour
    }
  }

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: panel.card
  }

  WatchedFile {
    id: historyFile
    path: root.historyPath
    atomicWrites: true
    onLoaded: {
      root.loadHistory(text())
      if (!root.imagesSwept) { root.imagesSwept = true; imageSweepTimer.start() }
    }
    onLoadFailed: root.loadHistory("[]")
  }

  Process {
    id: initProc
    command: ["pkill", "-f", "wl-paste .*--watch .*/quickshell/plugins/clipboard/capture\\.nu"]
    onExited: {
      currentProc.running = true
      textWatchProc.running = true
      imageWatchProc.running = true
    }
  }

  Process {
    id: currentProc
    command: [root.pluginDir + "/capture.nu"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.addClipboardJson(text)
    }
  }

  Process {
    id: textWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.pluginDir + "/capture.nu", "text"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser { onRead: function(data) { root.addClipboardJson(data) } }
  }

  Process {
    id: imageWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image/png", "--watch", root.pluginDir + "/capture.nu", "image/png"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser { onRead: function(data) { root.addClipboardJson(data) } }
  }

  Timer {
    id: watchRestartTimer
    interval: 1000
    onTriggered: {
      if (!textWatchProc.running) textWatchProc.running = true
      if (!imageWatchProc.running) imageWatchProc.running = true
    }
  }

  IpcHandler {
    target: "clipboard"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
    function forget(hash: string): string { root.forgetTextHash(hash); return "ok" }
  }

  OverlayCard {
    id: panel
    open: root.opened && !root.gpgHidden
    name: "clipboard"
    title: "clipboard"
    suffix: "[" + displayModel.count + (displayModel.count < root.history.length ? "/" + root.history.length : "") + "]"
    prompt: true
    query: root.clearConfirmOpen ? "" : root.filterText
    placeholder: root.clearConfirmOpen ? "clear history? [y/N]" : "search clipboard"
    hints: root.clearConfirmOpen ? [["Y", "clear"], ["N/ESC", "cancel"]]
      : root.gpgMode === "encrypt" ? [["^/v", "key"], ["SPACE", "pick"], ["ENTER", "encrypt"], ["ESC", "back"]]
      : root.gpgMode === "decrypt" ? [["^/v", "scroll"], ["ESC", "back"]]
      : [["ENTER", "copy"], ["SHIFT+ENTER", "paste"], ["ALT+ENTER", "open"], ["DEL", "forget"], ["SHIFT+DEL", "clear"], ["CTRL+E", "encrypt"], ["CTRL+D", "decrypt"], ["ESC", "close"]]
    keyboard: !root.gpgBusy
    cardWidth: Style.space(700)
    onDismissed: root.close()

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (root.clearConfirmOpen) {
          if (event.key === Qt.Key_Y) root.confirmClearHistory()
          else if (!event.isAutoRepeat && event.key !== Qt.Key_Shift) root.cancelClearHistory()
          event.accepted = true
          return
        }
        if (root.gpgMode !== "") {
          event.accepted = root.gpgKey(event)
          return
        }
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        if (ctrl) {
          if (event.key === Qt.Key_E) root.startEncrypt()
          else if (event.key === Qt.Key_D) root.startDecrypt()
          event.accepted = event.key === Qt.Key_E || event.key === Qt.Key_D
          if (event.accepted) return
        }

        if (event.key === Qt.Key_Escape) {
          if (root.filterText) root.setFilter("")
          else root.close()
        } else if (event.key === Qt.Key_Delete) {
          if (event.modifiers & Qt.ShiftModifier) root.requestClearHistory()
          else root.removeDisplayIndex(root.selectedIndex)
        } else if (event.key === Qt.Key_Up || Util.isPrev(event.key, event.modifiers)) root.select(-1)
        else if (event.key === Qt.Key_Down || Util.isNext(event.key, event.modifiers)) root.select(1)
        else if (ctrl && event.key === Qt.Key_U) root.setFilter("")
        else if (event.key === Qt.Key_PageUp) root.select(-6)
        else if (event.key === Qt.Key_PageDown) root.select(6)
        else if (event.key === Qt.Key_Home) root.selectAbsolute(0)
        else if (event.key === Qt.Key_End) root.selectAbsolute(displayModel.count - 1)
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          const row = root.rowAt(root.selectedIndex)
          if (event.modifiers & Qt.AltModifier) root.openRow(row)
          else root.copyRow(row, (event.modifiers & Qt.ShiftModifier) !== 0)
        } else if (Util.isWordDelete(event.key, event.modifiers)) root.setFilter(Util.wordDelete(root.filterText))
        else if (event.key === Qt.Key_Backspace) root.setFilter(root.filterText.slice(0, -1))
        else if (Util.printable(event.text))
          root.setFilter(root.filterText + event.text)
        else return
        event.accepted = true
      }
    }

    Item {
      anchors.fill: parent

      Row {
        anchors.fill: parent

        Item {
          width: parent.width / 2
          height: parent.height
          clip: true

          ListView {
            id: resultList
            anchors.fill: parent
            anchors.rightMargin: root.contentMargin
            model: displayModel
            clip: true
            spacing: Style.spacing.xs
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: rowDelegate
              required property int index
              required property string entryType
              required property string previewText
              required property string fullText
              required property string previewImage

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

              width: ListView.view.width
              height: root.rowHeight
              radius: Style.shape.data
              opacity: panel.boot.rowOpacity(index)
              color: hasCursor ? Colors.menu.selectedBackground
                : index === root.selectedIndex ? Style.hoverFill : "transparent"

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.md
                anchors.rightMargin: Style.spacing.md
                anchors.topMargin: Style.spacing.sm
                anchors.bottomMargin: Style.spacing.sm
                spacing: Style.spacing.md

                Label {
                  id: reticle
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(12)
                  text: rowDelegate.hasCursor ? ">" : ""
                  color: Colors.accentText
                  horizontalAlignment: Text.AlignHCenter
                  layer.enabled: rowDelegate.hasCursor && Style.fx.glow > 0
                  layer.effect: Glow {}
                }

                Image {
                  visible: rowDelegate.previewImage.length > 0
                  width: visible ? parent.height : 0
                  height: parent.height
                  source: rowDelegate.previewImage
                  sourceSize.height: Math.ceil(parent.height * Screen.devicePixelRatio)
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                }

                Label {
                  width: parent.width - reticle.width - parent.spacing - (rowDelegate.previewImage.length > 0 ? parent.height + parent.spacing : 0)
                  height: parent.height
                  text: rowDelegate.previewText
                  dim: rowDelegate.entryType === "image" || rowDelegate.entryType === "file"
                  highlighted: rowDelegate.index === root.selectedIndex
                  color: rowDelegate.hasCursor ? Colors.menu.selectedText : dim && !highlighted ? Colors.textDim : Colors.menu.text
                  elide: Text.ElideRight
                  verticalAlignment: Text.AlignVCenter
                  layer.enabled: rowDelegate.hasCursor && Style.fx.glow > 0
                  layer.effect: Glow {}
                }
              }

              HudFrame { shown: rowDelegate.hasCursor }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(rowDelegate.index, rowDelegate, mouse)
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = rowDelegate.index
                  root.copyRow(root.rowAt(rowDelegate.index))
                }
              }
            }

            EmptyState {
              shown: displayModel.count === 0
              glyph: "\u{f014c}"
              glyphSize: Style.font.displayLarge
              text: root.filterText ? "> NO MATCH" : "> NOTHING HERE"
            }
          }
        }

        Item {
          width: parent.width / 2
          height: parent.height
          clip: true

          property var activeRow: root.rowAt(root.selectedIndex)

          Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Style.normalBorderWidth
            color: Colors.edge
          }

          PanelSectionHeader {
            id: previewLabel
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.leftMargin: root.contentMargin
            text: root.gpgMode === "encrypt" ? "encrypt to" : root.gpgMode === "decrypt" ? "decrypted" : "preview"
          }

          Label {
            visible: root.gpgMode === "" && parent.activeRow && !parent.activeRow.previewImage
            anchors.fill: parent
            anchors.leftMargin: root.contentMargin
            anchors.topMargin: previewLabel.height + Style.spacing.xs
            text: parent.activeRow ? parent.activeRow.paneText : ""
            color: Colors.menu.text
            wrapMode: Text.WrapAnywhere
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
          }

          Image {
            visible: root.gpgMode === "" && parent.activeRow && parent.activeRow.previewImage
            anchors.fill: parent
            anchors.leftMargin: root.contentMargin
            anchors.topMargin: previewLabel.height + Style.spacing.xs
            source: parent.activeRow ? parent.activeRow.previewImage : ""
            sourceSize.width: Math.ceil(width * Screen.devicePixelRatio)
            fillMode: Image.PreserveAspectFit
            verticalAlignment: Image.AlignTop
            asynchronous: true
          }

          Column {
            visible: root.gpgMode !== ""
            anchors.fill: parent
            anchors.leftMargin: root.contentMargin
            anchors.topMargin: previewLabel.height + Style.spacing.xs
            spacing: Style.spacing.sm

            Label {
              width: parent.width
              visible: text !== ""
              text: root.gpgBusy ? "> WAITING FOR GPG" : root.gpgError
              color: root.gpgBusy ? Colors.menu.text : Colors.urgentText
              wrapMode: Text.Wrap
            }

            Label {
              width: parent.width
              visible: root.gpgMode === "decrypt" && root.gpgResult !== null
              text: root.gpgResult ? root.signatureLine(root.gpgResult.signature) : ""
              color: root.gpgResult ? root.signatureColor(root.gpgResult.signature) : Colors.menu.text
              font.bold: true
              wrapMode: Text.Wrap
            }

            Flickable {
              id: plainFlick
              width: parent.width
              height: parent.height - y
              visible: root.gpgMode === "decrypt" && root.gpgResult !== null
              clip: true
              contentHeight: plainText.implicitHeight
              boundsBehavior: Flickable.StopAtBounds

              Label {
                id: plainText
                width: plainFlick.width
                text: root.gpgResult ? root.gpgResult.plaintext : ""
                color: Colors.menu.text
                wrapMode: Text.WrapAnywhere
                onTextChanged: plainFlick.contentY = 0
              }
            }

            ListView {
              width: parent.width
              height: parent.height - y
              visible: root.gpgMode === "encrypt"
              model: root.gpgKeys
              clip: true
              spacing: Style.spacing.xs
              currentIndex: root.gpgKeyIndex
              onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

              delegate: Rectangle {
                id: keyRow
                required property int index
                required property var modelData
                readonly property bool hasCursor: index === root.gpgKeyIndex
                readonly property bool picked: root.gpgPicked[modelData.fpr] === true

                width: ListView.view.width
                height: keyText.implicitHeight + Style.spacing.sm * 2
                radius: Style.shape.data
                color: hasCursor ? Colors.menu.selectedBackground : "transparent"

                Label {
                  id: keyText
                  anchors.fill: parent
                  anchors.margins: Style.spacing.sm
                  text: (keyRow.picked ? "[x] " : "[ ] ") + keyRow.modelData.uid + (keyRow.modelData.own ? "  (own)"
                    : keyRow.modelData.valid ? "" : "  (not certified)")
                    + "\n    " + keyRow.modelData.fpr
                  color: keyRow.hasCursor ? Colors.menu.selectedText : Colors.menu.text
                  caption: true
                  elide: Text.ElideRight
                }

                HudFrame { shown: keyRow.hasCursor }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.gpgKeyIndex = keyRow.index
                    root.gpgToggleKey(keyRow.index)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
