import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "../../services"

// New widget, not a port of omarchy-shell's plugins/menu/Menu.qml.
Item {
  id: root

  property AppLibrary appLibrary: null
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property var entries: []

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
  property int cardWidth: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(480), panel.height - Style.gapsOut * 2)
  property int rowHeight: Style.space(44)
  property int iconSize: Style.space(28)

  function open() {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    if (root.appLibrary) root.appLibrary.refreshIcons()
    root.rebuildEntries()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function rebuildEntries() {
    root.entries = root.appLibrary ? root.appLibrary.sortedEntries(root.filterText) : []
    if (root.selectedIndex >= root.entries.length) root.selectedIndex = Math.max(0, root.entries.length - 1)
    else if (root.selectedIndex < 0) root.selectedIndex = 0
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    root.rebuildEntries()
  }

  function launchAt(index) {
    if (!root.appLibrary || index < 0 || index >= root.entries.length) return
    var entry = root.entries[index]
    root.appLibrary.launch(entry.id, root.appLibrary.entryName(entry))
    root.close()
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { if (root.opened) root.rebuildEntries() }
  }

  IpcHandler {
    target: "appsearch"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell-appsearch"
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
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.selectedIndex = Math.max(0, root.selectedIndex - 1)
            resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.selectedIndex = Math.min(root.entries.length - 1, root.selectedIndex + 1)
            resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.selectedIndex = Math.max(0, root.selectedIndex - 6)
            resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.selectedIndex = Math.min(root.entries.length - 1, root.selectedIndex + 6)
            resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectedIndex = 0
            resultList.positionViewAtIndex(0, ListView.Contain)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectedIndex = root.entries.length - 1
            resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.launchAt(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            root.setFilter(root.filterText.slice(0, -1))
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // Uppercase tracked section header, terminal-readout style.
        Row {
          id: titleRow
          width: parent.width
          spacing: Style.spacing.md

          Text {
            textFormat: Text.PlainText
            text: "APPLICATIONS"
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
            // Bracketed live match count.
            text: "[" + String(root.entries.length) + "]"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          // Terminal prompt line: `> query_` with a blinking block caret.
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
              text: root.filterText || "Search applications..."
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

        ListView {
          id: resultList
          width: parent.width
          height: parent.height - titleRow.height - root.headerHeight - root.contentSpacing * 2
          clip: true
          model: root.entries
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            id: rowDelegate
            required property var modelData
            required property int index

            width: ListView.view.width
            height: root.rowHeight
            radius: root.cornerRadius
            color: index === root.selectedIndex ? root.selectedBackground
              : rowMouse.containsMouse ? Style.hoverFill : "transparent"

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(10)

              // Reticle marker on the focused row.
              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(14)
                textFormat: Text.PlainText
                text: rowDelegate.index === root.selectedIndex ? ">" : ""
                color: root.selectedText
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                layer.enabled: rowDelegate.index === root.selectedIndex && Style.fx.glow > 0
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
                anchors.verticalCenter: parent.verticalCenter
                width: root.iconSize
                height: root.iconSize
                sourceSize.width: Math.round(root.iconSize * Screen.devicePixelRatio)
                sourceSize.height: Math.round(root.iconSize * Screen.devicePixelRatio)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                source: root.appLibrary ? root.appLibrary.iconSource(rowDelegate.modelData.icon) : ""
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - root.iconSize - Style.space(14) - parent.spacing * 2

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.appLibrary ? root.appLibrary.entryName(rowDelegate.modelData) : ""
                  color: rowDelegate.index === root.selectedIndex ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  // Neon bloom on the focused result.
                  layer.enabled: rowDelegate.index === root.selectedIndex && Style.fx.glow > 0
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
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: text.length > 0
                  text: root.appLibrary ? root.appLibrary.entrySubtext(rowDelegate.modelData) : ""
                  color: rowDelegate.index === root.selectedIndex ? root.selectedText : root.foreground
                  opacity: 0.6
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }
            }

            // HUD reticle on the focused result.
            HudFrame { visible: rowDelegate.index === root.selectedIndex && Style.fx.brackets }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              // Deliberately does NOT drive root.selectedIndex, on hover OR move.
              onClicked: root.launchAt(rowDelegate.index)
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: root.entries.length === 0
            width: parent.width * 0.8

            Text {
              text: "󰀻"
              color: root.selectedText
              opacity: 0.8
              font.family: Style.font.iconFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: "No matching applications"
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

      // Terminal-panel framing over the launcher card.
      HudFrame {}
    }

    // CRT scanline overlay across the whole launcher overlay.
    Scanlines {}
  }
}
