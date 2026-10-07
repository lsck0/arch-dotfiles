import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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

  readonly property string historyPath: Paths.state + "/clipboard-history.json"
  readonly property int historyLimit: 500

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.shape.surface
  property string fontFamily: Style.font.family
  property int contentMargin: Style.spacing.panelPadding
  property int rowHeight: Style.space(44)

  function open() {
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
    root.opened = false
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
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  function cancelClearHistory() {
    root.clearConfirmOpen = false
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmClearHistory() {
    root.history = []
    root.saveHistory()
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
    root.history = ClipboardHistory.removeEntryAt(root.history, row.historyIndex)
    root.saveHistory()

    if (displayModel.count <= 1) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count - 1) {
      root.selectedIndex = displayModel.count - 2
    }

    root.disarmPointer()
    root.rebuildDisplay()
  }

  // gpg-clip passes the md5 of the plaintext it encrypted, so the text itself never crosses argv
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
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      displayModel.append({
        entryType: row.entryType,
        fullText: row.fullText,
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
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
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

  function copyRow(row) {
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached(["bash", "-c", "wl-copy --type " + Util.shellQuote(row.mime) + " < " + Util.shellQuote(row.path)])
    } else if (row.fullText) {
      Quickshell.execDetached(["bash", "-c", "printf '%s' " + Util.shellQuote(row.fullText) + " | wl-copy"])
    }
  }

  function openRow(row) {
    if (!row) return
    root.opened = false
    Quickshell.execDetached(["xdg-open", row.path || row.fullText])
  }

  Component.onCompleted: initProc.running = true

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
      Util.rearmWatch(this)
    }
    onLoadFailed: root.loadHistory("[]")
    onFileChanged: reload()
  }

  // reap watchers left by a previous shell
  Process {
    id: initProc
    command: ["pkill", "-f", "wl-paste .*--watch .*/quickshell/plugins/clipboard/capture\\.sh"]
    onExited: {
      currentProc.running = true
      textWatchProc.running = true
      imageWatchProc.running = true
    }
  }

  Process {
    id: currentProc
    command: [root.pluginDir + "/capture.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.addClipboardJson(text)
    }
  }

  Process {
    id: textWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.pluginDir + "/capture.sh", "text"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser { onRead: function(data) { root.addClipboardJson(data) } }
  }

  Process {
    id: imageWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image/png", "--watch", root.pluginDir + "/capture.sh", "image/png"]
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
    open: root.opened
    name: "clipboard"
    title: "clipboard"
    suffix: "[" + String(displayModel.count) + "]"
    prompt: true
    query: root.filterText
    placeholder: "search clipboard"
    hints: [["ESC", "close"], ["ENTER", "copy"], ["ALT+ENTER", "open"], ["DEL", "forget"]]
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
              // selected row keeps a faint fill before the cursor engages
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
                  // decode at row height, not full size
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
              visible: displayModel.count === 0
              width: parent.width * 0.8

              Text {
                text: "\u{f014c}"
                color: root.selectedText
                opacity: 0.8
                font.family: Style.font.iconFamily
                font.pixelSize: Style.font.displayLarge
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: "> NOTHING HERE"
                color: root.foreground
                opacity: 0.7
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
            color: Util.alpha(Color.menu.border, 0.28)
          }

          PanelSectionHeader {
            id: previewLabel
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.leftMargin: root.contentMargin
            text: "preview"
          }

          Text {
            textFormat: Text.PlainText
            visible: parent.activeRow && !parent.activeRow.previewImage
            anchors.fill: parent
            anchors.leftMargin: root.contentMargin
            anchors.topMargin: previewLabel.height + Style.spacing.xs
            text: parent.activeRow ? parent.activeRow.fullText : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WrapAnywhere
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
          }

          Image {
            visible: parent.activeRow && parent.activeRow.previewImage
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
        }
      }
    }
  }
}
