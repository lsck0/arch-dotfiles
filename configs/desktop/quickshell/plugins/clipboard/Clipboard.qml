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
  // the startup sweep waits so the current-clipboard capture can land in history first
  readonly property int imageSweepDelayMs: 3000
  property bool imagesSwept: false

  property color background: Colors.menu.background
  property color foreground: Colors.menu.text
  property color scrim: Colors.menu.scrim
  property color selectedBackground: Colors.menu.selectedBackground
  property color selectedText: Colors.menu.selectedText
  readonly property int cornerRadius: Style.shape.surface
  property string fontFamily: Style.font.family
  property int contentMargin: Style.spacing.panelPadding
  property int rowHeight: Style.space(44)

  function open() {
    root.gpgReset()
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = false
    root.disarmPointer()
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

  function selectedEntryText() {
    var row = displayModel.count > 0 ? displayModel.get(root.selectedIndex) : null
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
    if (!sig) return root.foreground
    if (sig.state === "good") return Colors.ok
    if (sig.state === "untrusted" || sig.state === "expired") return Colors.warn
    if (sig.state === "none") return root.foreground
    return Colors.urgent
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function loadHistory(raw) {
    root.history = ClipboardHistory.parseHistory(raw)
    if (root.opened) root.rebuildDisplay()
  }

  function saveHistory() {
    historyFile.setText(JSON.stringify(root.history.slice(0, root.historyLimit), null, 2) + "\n")
  }

  function addClipboardJson(line) {
    var normalized = ClipboardHistory.parseEntryJson(line)
    if (!normalized) return
    root.history = ClipboardHistory.addEntry(root.history, normalized, root.historyLimit)
    root.saveHistory()
    if (root.opened) root.rebuildDisplay()
  }

  function requestClearHistory() {
    if (root.history.length === 0) return
    clearConfirm.selectedIndex = 0
    root.clearConfirmOpen = true
  }

  function cancelClearHistory() {
    root.clearConfirmOpen = false
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
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
    const images = root.imagePaths()
    root.history = []
    root.saveHistory()
    for (let i = 0; i < images.length; i++) Quickshell.execDetached(["rm", "-f", "--", images[i]])
    root.selectedIndex = 0
    root.cursorActive = false
    root.disarmPointer()
    root.clearConfirmOpen = false
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
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

    root.disarmPointer()
    root.rebuildDisplay()
  }

  function forgetTextHash(hash) {
    var next = root.history.filter(function(entry) { return entry.type !== "text" || Qt.md5(entry.text) !== hash })
    if (next.length === root.history.length) return
    root.history = next
    root.saveHistory()
    if (root.opened) root.rebuildDisplay()
  }

  function rebuildDisplay() {
    var rows = ClipboardHistory.displayRows(root.history, root.filterText, 50)

    displayModel.clear()
    for (let i = 0; i < rows.length; i++) {
      let row = rows[i]
      displayModel.append({
        entryType: row.entryType,
        fullText: row.fullText,
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
    root.disarmPointer()
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
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.copyRow(displayModel.get(index))
  }

  function openIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.openRow(displayModel.get(index))
  }

  function copyText(text) {
    if (copyTextProc.running) return
    copyTextProc.stdinEnabled = true
    copyTextProc.running = true
    copyTextProc.write(text)
    copyTextProc.stdinEnabled = false
  }

  function copyRow(row) {
    if (!row) return
    root.close()
    if (row.entryType === "image") {
      Quickshell.execDetached(["bash", "-c", "wl-copy --type " + Util.shellQuote(row.mime) + " < " + Util.shellQuote(row.path)])
    } else if (row.fullText) {
      root.copyText(row.fullText)
    }
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
    id: gpgHideTimer
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
    repeat: false
    onTriggered: root.sweepImageFiles()
  }

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: panel.card
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.loadHistory(text())
      if (!root.imagesSwept) { root.imagesSwept = true; imageSweepTimer.start() }
      Util.rearmWatch(this)
    }
    onLoadFailed: root.loadHistory("[]")
    onFileChanged: reload()
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
    repeat: false
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
    suffix: "[" + String(displayModel.count) + "]"
    prompt: true
    query: root.filterText
    placeholder: "search clipboard"
    hints: root.gpgMode === "encrypt" ? [["ESC", "back"], ["UP/DOWN", "key"], ["SPACE", "pick"], ["ENTER", "encrypt"]]
      : root.gpgMode === "decrypt" ? [["ESC", "back"]]
      : [["ESC", "close"], ["ENTER", "copy"], ["ALT+ENTER", "open"], ["DEL", "forget"], ["SHIFT+DEL", "clear"], ["CTRL+E", "encrypt"], ["CTRL+D", "decrypt"]]
    keyboard: !root.gpgBusy
    cardWidth: Style.space(700)
    cardHeight: Style.space(480)
    onDismissed: root.close()

    Item {
      id: keyCatcher
      anchors.fill: parent
      z: root.clearConfirmOpen ? 20 : 0
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (root.clearConfirmOpen) {
          if (clearConfirm.handleKey(event)) event.accepted = true
          return
        }
        if (root.gpgMode !== "") {
          event.accepted = root.gpgKey(event)
          return
        }
        if (event.modifiers & Qt.ControlModifier) {
          if (event.key === Qt.Key_E) root.startEncrypt()
          else if (event.key === Qt.Key_D) root.startDecrypt()
          event.accepted = event.key === Qt.Key_E || event.key === Qt.Key_D
          if (event.accepted) return
        }

        if (event.key === Qt.Key_Escape) {
          if (root.filterText) root.setFilter("")
          else root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Delete) {
          if (event.modifiers & Qt.ShiftModifier) root.requestClearHistory()
          else root.removeDisplayIndex(root.selectedIndex)
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          root.select(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.select(1)
          event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
          root.select(-6)
          event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
          root.select(6)
          event.accepted = true
        } else if (event.key === Qt.Key_Home) {
          root.selectAbsolute(0)
          event.accepted = true
        } else if (event.key === Qt.Key_End) {
          root.selectAbsolute(displayModel.count - 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (root.cursorActive && (event.modifiers & Qt.AltModifier)) root.openIndex(root.selectedIndex)
          else if (root.cursorActive) root.activateIndex(root.selectedIndex)
          else if (displayModel.count > 0) root.cursorActive = true
          event.accepted = true
        } else if (event.key === Qt.Key_Backspace) {
          root.setFilter(root.filterText.slice(0, -1))
          event.accepted = true
        } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
          root.setFilter(root.filterText + event.text)
          event.accepted = true
        }
      }

      ConfirmDialog {
        id: clearConfirm

        anchors.fill: parent
        opened: root.clearConfirmOpen
        z: 10
        message: "Delete entire clipboard history?"
        confirmText: "Delete"
        background: root.background
        foreground: root.foreground
        scrim: root.scrim
        selectedBackground: root.selectedBackground
        selectedText: root.selectedText
        fontFamily: root.fontFamily
        cornerRadius: root.cornerRadius
        onCanceled: root.cancelClearHistory()
        onConfirmed: root.confirmClearHistory()
      }
    }

    Item {
      anchors.fill: parent

      Row {
        anchors.fill: parent
        spacing: 0

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
              color: hasCursor ? root.selectedBackground
                : index === root.selectedIndex ? Style.hoverFill : "transparent"

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.md
                anchors.rightMargin: Style.spacing.md
                anchors.topMargin: Style.spacing.sm
                anchors.bottomMargin: Style.spacing.sm
                spacing: Style.spacing.md

                Text {
                  id: reticle
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(12)
                  textFormat: Text.PlainText
                  text: rowDelegate.hasCursor ? ">" : ""
                  color: root.selectedText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
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
                  smooth: true
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width - reticle.width - parent.spacing - (rowDelegate.previewImage.length > 0 ? parent.height + parent.spacing : 0)
                  height: parent.height
                  text: rowDelegate.previewText
                  color: rowDelegate.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  opacity: rowDelegate.entryType === "image" || rowDelegate.entryType === "file" ? 0.72 : 1.0
                  elide: Text.ElideRight
                  wrapMode: Text.NoWrap
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
                  root.activateIndex(rowDelegate.index)
                }
              }
            }

            Column {
              anchors.centerIn: parent
              spacing: Style.spacing.sm
              opacity: displayModel.count === 0 ? 1 : 0
              visible: opacity > 0
              Behavior on opacity { NumberAnimation { duration: Style.motion.base; easing.type: Style.motion.fastEasing } }
              width: parent.width * 0.8

              Text {
                text: "\u{f014c}"
                color: root.selectedText
                opacity: Style.emphasis.dim
                font.family: Style.font.iconFamily
                font.pixelSize: Style.font.displayLarge
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: "> NOTHING HERE"
                color: root.foreground
                opacity: Style.emphasis.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
              }
            }
          }
        }

        Item {
          width: parent.width / 2
          height: parent.height
          clip: true

          property var activeRow: displayModel.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count ? displayModel.get(root.selectedIndex) : null

          Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Style.normalBorderWidth
            color: Util.alpha(Colors.menu.border, 0.28)
          }

          PanelSectionHeader {
            id: previewLabel
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.leftMargin: root.contentMargin
            text: root.gpgMode === "encrypt" ? "encrypt to" : root.gpgMode === "decrypt" ? "decrypted" : "preview"
          }

          Text {
            textFormat: Text.PlainText
            visible: root.gpgMode === "" && parent.activeRow && !parent.activeRow.previewImage
            anchors.fill: parent
            anchors.leftMargin: root.contentMargin
            anchors.topMargin: previewLabel.height + Style.spacing.xs
            text: parent.activeRow ? parent.activeRow.paneText : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
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
            smooth: true
          }

          Column {
            visible: root.gpgMode !== ""
            anchors.fill: parent
            anchors.leftMargin: root.contentMargin
            anchors.topMargin: previewLabel.height + Style.spacing.xs
            spacing: Style.spacing.sm

            Text {
              width: parent.width
              visible: text !== ""
              textFormat: Text.PlainText
              text: root.gpgBusy ? "> waiting for gpg (pinentry or a key touch may ask)" : root.gpgError
              color: root.gpgBusy ? root.foreground : Colors.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }

            Text {
              width: parent.width
              visible: root.gpgMode === "decrypt" && root.gpgResult !== null
              textFormat: Text.PlainText
              text: root.gpgResult ? root.signatureLine(root.gpgResult.signature) : ""
              color: root.gpgResult ? root.signatureColor(root.gpgResult.signature) : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              wrapMode: Text.Wrap
            }

            Text {
              width: parent.width
              height: parent.height - y
              visible: root.gpgMode === "decrypt" && root.gpgResult !== null
              textFormat: Text.PlainText
              text: root.gpgResult ? root.gpgResult.plaintext : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WrapAnywhere
              elide: Text.ElideRight
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
                color: hasCursor ? root.selectedBackground : "transparent"

                Text {
                  id: keyText
                  anchors.fill: parent
                  anchors.margins: Style.spacing.sm
                  textFormat: Text.PlainText
                  text: (keyRow.picked ? "[x] " : "[ ] ") + keyRow.modelData.uid + (keyRow.modelData.own ? "  (own)"
                    : keyRow.modelData.valid ? "" : "  (not certified)")
                    + "\n    " + keyRow.modelData.fpr
                  color: keyRow.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
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
