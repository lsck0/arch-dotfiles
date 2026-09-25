import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory

// Upgraded from the earlier simplified port to match omarchy-shell's fuller Clipboard.qml: split list/preview pane, image thumbnails, PointerMoveGate (keyboard nav doesn't fight stationary-pointer hover churn), ConfirmDialog for Shift+Delete, BorderSurface chrome, and PageUp/PageDown/Home/End nav.
Item {
  id: root

  readonly property string pluginDir: Paths.plugin("clipboard")
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool clearConfirmOpen: false
  property var history: []

  readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/quickshell/clipboard-history.json"
  readonly property int historyLimit: 500

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.flat(border, Style.normalBorderWidth)
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.family
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(700), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(480), panel.height - Style.gapsOut * 2)
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
    root.history = ClipboardHistory.clearHistory()
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
      // Both interpolations quoted.
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
    referenceItem: card
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("[]")
    onFileChanged: reload()
  }

  // Best-effort reap of watchers left behind by a previous shell instance.
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
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

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

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // Uppercase tracked section header with live bracketed entry count, terminal-readout style.
        Row {
          id: titleRow
          width: parent.width
          spacing: Style.spacing.md

          Text {
            textFormat: Text.PlainText
            text: "CLIPBOARD"
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            font.letterSpacing: Style.headerTracking
            layer.enabled: Style.fx.glow > 0
            layer.effect: MultiEffect {
              shadowEnabled: true
              shadowColor: Style.fx.glowColor
              shadowBlur: 1.0
              shadowVerticalOffset: 0
              shadowHorizontalOffset: 0
              blurMax: Style.fx.glowRadius
              autoPaddingEnabled: true
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "[" + String(displayModel.count) + "]"
            color: root.foreground
            opacity: Style.emphasis.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          // Terminal prompt line: `> query _` with a blinking block caret.
          Row {
            id: promptRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.md

            Text {
              id: promptGlyph
              textFormat: Text.PlainText
              text: ">"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              layer.enabled: Style.fx.glow > 0
              layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Style.fx.glowColor
                shadowBlur: 1.0
                shadowVerticalOffset: 0
                shadowHorizontalOffset: 0
                blurMax: Style.fx.glowRadius
                autoPaddingEnabled: true
              }
            }

            Text {
              id: queryText
              textFormat: Text.PlainText
              // Hug the typed text so the caret follows it; cap and elide when long.
              width: Math.min(implicitWidth, promptRow.width - promptGlyph.width - caret.width - promptRow.spacing * 2)
              text: root.filterText || "Search clipboard..."
              color: root.foreground
              opacity: root.filterText ? 1 : 0.58
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              elide: Text.ElideRight
            }

            // Blinking block caret at the input head.
            Text {
              id: caret
              textFormat: Text.PlainText
              text: "_"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              layer.enabled: Style.fx.glow > 0
              layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Style.fx.glowColor
                shadowBlur: 1.0
                shadowVerticalOffset: 0
                shadowHorizontalOffset: 0
                blurMax: Style.fx.glowRadius
                autoPaddingEnabled: true
              }
              SequentialAnimation on opacity {
                running: root.opened
                loops: Animation.Infinite
                PropertyAnimation { to: 1; duration: 0 }
                PauseAnimation { duration: 530 }
                PropertyAnimation { to: 0; duration: 0 }
                PauseAnimation { duration: 530 }
              }
            }
          }

          // Hard accent underline: the terminal input line.
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.max(1, Style.space(2))
            color: Util.alpha(Color.accent, Style.fx.glow > 0 ? 0.9 : 0.55)
          }
        }

        Item {
          width: parent.width
          height: parent.height - titleRow.height - root.headerHeight - root.contentSpacing * 2

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
                spacing: Style.space(4)
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
                  radius: root.cornerRadius
                  // The previewed row keeps a faint fill before the cursor is engaged, so the preview pane always points at a visible row.
                  color: hasCursor ? root.selectedBackground
                    : index === root.selectedIndex ? Style.hoverFill : "transparent"

                  Row {
                    id: rowContent
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(12)
                    anchors.topMargin: Style.space(6)
                    anchors.bottomMargin: Style.space(6)
                    spacing: Style.space(10)

                    // Reticle marker on the row under the cursor.
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
                      layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Style.fx.glowColor
                        shadowBlur: 1.0
                        shadowVerticalOffset: 0
                        shadowHorizontalOffset: 0
                        blurMax: Style.fx.glowRadius
                        autoPaddingEnabled: true
                      }
                    }

                    Image {
                      visible: rowDelegate.previewImage.length > 0
                      width: visible ? parent.height : 0
                      height: parent.height
                      source: rowDelegate.previewImage
                      // Clipboard images are usually screenshots; this draws them at row height, so decoding at full size held a multi-megabyte buffer per visible row.
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
                      // Neon bloom on the row under the cursor.
                      layer.enabled: rowDelegate.hasCursor && Style.fx.glow > 0
                      layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Style.fx.glowColor
                        shadowBlur: 1.0
                        shadowVerticalOffset: 0
                        shadowHorizontalOffset: 0
                        blurMax: Style.fx.glowRadius
                        autoPaddingEnabled: true
                      }
                    }
                  }

                  // HUD reticle on the row under the cursor.
                  HudFrame { visible: rowDelegate.hasCursor && Style.fx.brackets }

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
                  spacing: Style.space(8)
                  visible: displayModel.count === 0
                  width: parent.width * 0.8

                  Text {
                    text: "󰅌"
                    color: root.selectedText
                    opacity: 0.8
                    font.family: Style.font.iconFamily
                    font.pixelSize: Style.font.displayLarge
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: root.history.length === 0 ? "Clipboard is empty" : "No matches"
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
                color: Util.alpha(root.border, 0.28)
              }

              // Uppercase tracked pane label, terminal-readout style.
              Text {
                id: previewLabel
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.leftMargin: root.contentMargin
                textFormat: Text.PlainText
                text: ":: PREVIEW"
                color: Color.accent
                opacity: Style.emphasis.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: Style.headerTracking
              }

              Text {
                textFormat: Text.PlainText
                visible: parent.activeRow && !parent.activeRow.previewImage
                anchors.fill: parent
                anchors.leftMargin: root.contentMargin
                anchors.topMargin: previewLabel.height + Style.spacing.sm
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
                anchors.topMargin: previewLabel.height + Style.spacing.sm
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

      // Terminal-panel framing over the clipboard card.
      HudFrame {}
      Scanlines {}
    }
  }
}
