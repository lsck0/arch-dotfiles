import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "../../services"

// New widget, not a port of omarchy-shell's plugins/menu/Menu.qml. Upstream's
// menu is a full JSONC-config-driven, guard-scripted, multi-provider command
// palette (system actions, theme switching, settings toggles, app search —
// all one generic tree-navigation engine, ~1480 lines) — the "Apps" search
// is just one provider plugged into that. Building the whole engine to
// replace walker (an app launcher) would be large scope creep past what was
// actually asked for, and would duplicate widgets this repo already has
// (Battery/Network/Bluetooth panels etc. already cover the non-app parts of
// upstream's menu). This is a purpose-built app search/launcher instead,
// styled like Clipboard.qml's overlay, backed entirely by the existing
// shared services/AppLibrary.qml + AppSearch.js (already ported in Phase 2
// for this exact consumer, per AppLibrary.qml's own header comment).
// Deliberately does not wire AppLibrary.remove() — no local equivalent of
// omarchy-remove-launcher-entry exists (see AppLibrary.qml), so there is no
// delete-entry action here rather than a dead button.
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

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || "Search applications…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        ListView {
          id: resultList
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing
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
            color: index === root.selectedIndex ? root.selectedBackground : "transparent"

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(10)

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
                width: parent.width - root.iconSize - parent.spacing

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.appLibrary ? root.appLibrary.entryName(rowDelegate.modelData) : ""
                  color: rowDelegate.index === root.selectedIndex ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
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

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectedIndex = rowDelegate.index
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
    }
  }
}
