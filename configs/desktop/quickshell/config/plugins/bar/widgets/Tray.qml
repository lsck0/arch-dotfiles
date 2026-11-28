pragma ComponentBehavior: Bound
import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "tray"
  barPriority: 85

  property bool managePopupOpen: false
  property bool trayMenuOpen: false
  property var activeTrayItem: null
  property var activeTrayAnchor: null
  readonly property var pinnedIds: settings.pinned instanceof Array ? settings.pinned : []
  readonly property var hiddenIds: settings.hidden instanceof Array ? settings.hidden : []
  // put back in the drawer by hand, against a tray_default of pinned or hidden
  readonly property var drawerIds: settings.drawer instanceof Array ? settings.drawer : []
  readonly property var pinnedItems: bucket("pinned")
  readonly property var drawerItems: bucket("drawer")
  readonly property var allItems: bucket("all")
  // unpinned icons past the cap and hidden ones fold into one "+N" slot that opens the manage popup; with none folded
  // it stays as a plain manage button, so an icon can always be hidden or brought back however few there are
  readonly property int drawerShownCountMax: 6
  readonly property var drawerShown: drawerItems.slice(0, drawerShownCountMax)
  readonly property int hiddenCount: allItems.length - pinnedItems.length - drawerItems.length
  readonly property int moreCount: drawerItems.length - drawerShown.length + hiddenCount
  readonly property int drawerCount: drawerShown.length + 1
  readonly property int trayItemExtent: Style.bar.iconSlot
  readonly property int trayItemGap: Style.bar.itemGap
  readonly property int drawerExtent: drawerCount > 0 ? drawerCount * trayItemExtent + (drawerCount - 1) * trayItemGap : 0

  property var submenuStack: []
  readonly property int submenuDepth: submenuStack.length
  readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
  readonly property var currentChildren: submenuDepth > 0
    ? submenuStack[submenuDepth - 1].opener.children
    : trayMenuOpener.children

  property bool menuLevelSettling: false

  Component {
    id: submenuOpenerComponent
    QsMenuOpener {}
  }

  Timer {
    id: menuLevelSettleTimer
    interval: 250
    onTriggered: root.menuLevelSettling = false
  }

  function settleMenuLevel() {
    menuLevelSettling = true
    menuLevelSettleTimer.restart()
  }

  function resetTrayMenu() {
    menuLevelSettling = false
    menuLevelSettleTimer.stop()
    trayMenuFlick.contentY = 0
    var openers = submenuStack
    submenuStack = []
    for (let i = openers.length - 1; i >= 0; i--) openers[i].opener.destroy()
  }

  function enterSubmenu(entry, title) {
    var opener = submenuOpenerComponent.createObject(root, { menu: entry })
    if (!opener) return
    var stack = submenuStack.slice()
    stack.push({ opener: opener, title: title })
    submenuStack = stack
    settleMenuLevel()
  }

  function leaveSubmenu() {
    if (submenuStack.length === 0) return
    var stack = submenuStack.slice()
    var top = stack.pop()
    submenuStack = stack
    top.opener.destroy()
    settleMenuLevel()
  }

  function close() {
    managePopupOpen = false
    trayMenuOpen = false
  }

  function openTrayMenu(item, anchorItem, mouse) {
    if (!item) return
    if (!item.menu) {
      if (!anchorItem || !anchorItem.QsWindow) return
      const point = anchorItem.QsWindow.contentItem.mapFromItem(anchorItem, mouse.x, mouse.y)
      item.display(anchorItem.QsWindow.window, point.x, point.y)
      return
    }

    resetTrayMenu()
    activeTrayItem = item
    activeTrayAnchor = anchorItem
    trayMenuOpen = true
  }

  function iconIsSymbolic(icon) {
    var name = String(icon || "").split("?")[0]
    return name.slice(-9) === "-symbolic"
  }

  // An app's own activate only raises its window, which hyprland marks urgent on another workspace (focus_on_activate
  // is off); the click asked for it, so its window is focused through the toplevel, which switches there.
  // Electron names its item <app>_status_icon_<n>; the window's app id may carry a reverse-dns prefix.
  function focusApp(item) {
    const keys = [String(item.id || "").replace(/_status_icon_\d+$/, ""), String(item.title || "")]
      .map(k => k.toLowerCase()).filter(k => k !== "")
    if (keys.length === 0) return
    const windows = ToplevelManager.toplevels.values.filter(t => {
      const app = String(t.appId).toLowerCase()
      return keys.some(k => app === k || app.endsWith("." + k))
    })
    if (windows.length > 0) windows[0].activate()
  }

  function trayTooltip(item) {
    return item.tooltipTitle || item.title || item.id || ""
  }

  // a hand-set place first, else the tray_default option's
  function placeOf(iid) {
    if (hiddenIds.indexOf(iid) !== -1) return "hidden"
    if (pinnedIds.indexOf(iid) !== -1) return "pinned"
    if (drawerIds.indexOf(iid) !== -1) return "drawer"
    return Prefs.trayDefault
  }

  function classifyItem(item) { return placeOf(String(item.id || "")) }

  function bucket(category) {
    return SystemTray.items.values // qmllint disable missing-property
      .filter(item => item.status !== Status.Passive && (category === "all" || classifyItem(item) === category))
  }

  // an id sits in at most one of the three lists: its hand-set place
  function placeSet(iid, place) {
    const without = list => list.filter(id => id !== iid)
    const lists = { pinned: without(pinnedIds), hidden: without(hiddenIds), drawer: without(drawerIds) }
    lists[place] = lists[place].concat([iid])
    if (!root.bar || !root.bar.shellHost) return
    root.bar.shellHost.setWidgetSettings("Tray", lists)
  }

  // pin or hide, or back to the drawer from there
  function togglePin(iid) { placeSet(iid, placeOf(iid) === "pinned" ? "drawer" : "pinned") }

  function toggleHide(iid) { placeSet(iid, placeOf(iid) === "hidden" ? "drawer" : "hidden") }

  // a tray icon's left click: its app (focused), or its menu where it has only that
  function activateItem(item, anchorItem, mouse) {
    if (item.onlyMenu) {
      root.openTrayMenu(item, anchorItem, mouse)
      return
    }
    item.activate()
    root.focusApp(item)
  }

  visible: allItems.length > 0
  implicitWidth: trayContent.implicitWidth

  Item {
    id: trayContent
    anchors.fill: parent
    implicitWidth: pinnedRow.implicitWidth + root.drawerExtent
    implicitHeight: Style.bar.sizeHorizontal

    containmentMask: QtObject {
      function contains(point: point): bool {
        if (point.y < 0 || point.y > trayContent.height) return false
        return point.x >= 0 && point.x <= trayContent.implicitWidth
      }
    }

    Item {
      width: root.drawerExtent
      height: Style.bar.sizeHorizontal
      visible: root.allItems.length > 0

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton) root.managePopupOpen = !root.managePopupOpen
        }
      }

      Item {
        anchors.verticalCenter: parent.verticalCenter
        width: root.drawerExtent
        height: Style.bar.sizeHorizontal
        clip: true

        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.trayItemGap

          Repeater {
            model: root.drawerShown
            TrayItem {}
          }

          WidgetButton {
            bar: root.bar
            fixedWidth: root.trayItemExtent
            fontSize: Style.font.caption
            hoverFill: true
            text: root.moreCount > 0 ? "+" + root.moreCount : "\u{f141}"
            tooltipText: (root.moreCount > 0
              ? Util.count(root.moreCount, "more tray icon") + (root.hiddenCount > 0 ? " (" + root.hiddenCount + " hidden)" : "")
              : "Tray icons") + " :: click to manage"
            onPressed: root.managePopupOpen = !root.managePopupOpen
          }
        }
      }
    }

    Row {
      id: pinnedRow
      x: root.drawerExtent
      anchors.verticalCenter: parent.verticalCenter
      spacing: root.trayItemGap
      leftPadding: root.pinnedItems.length > 0 && root.drawerCount > 0 ? Style.bar.groupGap : 0
      Repeater {
        model: root.pinnedItems
        TrayItem {}
      }
    }
  }

  PopupCard {
    id: managePopup
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.managePopupOpen
    contentWidth: managePopup.fittedContentWidth(Style.space(300))
    contentHeight: managePopup.fittedContentHeight(manageColumn.implicitHeight)

    Column {
      id: manageColumn
      anchors.fill: parent
      spacing: Style.spacing.sm

      PanelSectionHeader { text: "TRAY ICONS" }

      Label {
        visible: root.allItems.length === 0
        text: "> NO TRAY ICONS"
        dim: true
        caption: true
      }

      Repeater {
        model: root.allItems
        delegate: Item {
          id: rowRoot
          required property var modelData
          width: manageColumn.width
          implicitHeight: Style.row.control

          readonly property string itemId: String(modelData.id || "")
          readonly property string displayName: {
            var t = String(modelData.title || "").trim()
            if (t) return t
            var tt = String(modelData.tooltipTitle || "").trim()
            if (tt) return tt
            var id = String(modelData.id || "")
            var slash = id.lastIndexOf("/")
            return slash !== -1 ? id.substring(slash + 1) : (id || "Unknown")
          }
          readonly property bool isPinned: root.placeOf(itemId) === "pinned"
          readonly property bool isHidden: root.placeOf(itemId) === "hidden"

          // the icon and name act as its tray icon does: left opens the app, middle its secondary action, right its menu
          MouseArea {
            id: rowOpen
            anchors.left: parent.left
            anchors.right: rowHideBtn.left
            anchors.rightMargin: Style.spacing.sm
            height: parent.height
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onClicked: function(mouse) {
              if (mouse.button === Qt.MiddleButton) {
                rowRoot.modelData.secondaryActivate()
                return
              }
              if (mouse.button === Qt.RightButton) {
                root.openTrayMenu(rowRoot.modelData, rowOpen, mouse)
                return
              }
              const item = rowRoot.modelData
              if (!item.onlyMenu) root.managePopupOpen = false
              root.activateItem(item, rowOpen, mouse)
            }
          }

          Rectangle {
            anchors.fill: rowOpen
            radius: Style.shape.data
            color: rowOpen.containsMouse ? Style.hoverFill : "transparent"
          }

          TrayIcon {
            id: rowIcon
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: Style.bar.iconCanvas
            height: Style.bar.iconCanvas
            icon: rowRoot.modelData.icon
          }

          MenuText {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: rowIcon.right
            anchors.leftMargin: Style.spacing.md
            anchors.right: rowHideBtn.left
            anchors.rightMargin: Style.spacing.sm
            text: rowRoot.displayName
            elide: Text.ElideRight
          }

          Button {
            focusable: true
            id: rowPinBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            iconText: "\uf08d"
            text: rowRoot.isPinned ? "Unpin" : "Pin"
            foreground: Colors.bar.text
            iconSize: Style.font.bodySmall
            fontSize: Style.font.bodySmall
            onClicked: root.togglePin(rowRoot.itemId)
          }

          Button {
            focusable: true
            id: rowHideBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: rowPinBtn.left
            anchors.rightMargin: Style.spacing.sm
            iconText: "\uf06e"
            text: rowRoot.isHidden ? "Show" : "Hide"
            foreground: Colors.bar.text
            iconSize: Style.font.bodySmall
            fontSize: Style.font.bodySmall
            onClicked: root.toggleHide(rowRoot.itemId)
          }
        }
      }
    }
  }

  QsMenuOpener {
    id: trayMenuOpener
    menu: root.activeTrayItem ? root.activeTrayItem.menu : null
  }

  PopupCard {
    id: trayMenuPopup
    anchorItem: root.activeTrayAnchor || root
    owner: root
    bar: root.bar
    open: root.trayMenuOpen
    padding: Style.spacing.xs
    onVisibleChanged: if (!visible) root.resetTrayMenu()
    contentWidth: trayMenuPopup.fittedContentWidth(Style.space(232))
    contentHeight: trayMenuPopup.fittedContentHeight(menuHeaderHeight + trayMenuColumn.implicitHeight, Style.space(420))

    readonly property int menuHeaderHeight: menuHeader.visible ? menuHeader.implicitHeight : 0
    readonly property var menuEntries: root.currentChildren ? root.currentChildren.values : []
    readonly property bool hasCheckColumn: menuEntries.some(e => !e.isSeparator && e.buttonType !== QsMenuButtonType.None)
    readonly property bool hasIconColumn: menuEntries.some(e => !e.isSeparator && String(e.icon || "") !== "")
    readonly property int checkGutter: hasCheckColumn ? Style.space(22) : Style.space(8)
    readonly property int textInset: checkGutter + (hasIconColumn ? Style.space(22) : 0)

    Column {
      id: trayMenuLayout
      anchors.fill: parent

      Column {
        id: menuHeader
        visible: root.submenuDepth > 0
        width: trayMenuLayout.width

        Item {
          width: menuHeader.width
          implicitHeight: Style.space(30)

          Rectangle {
            anchors.fill: parent
            radius: Style.shape.data
            color: backMouse.containsMouse ? Style.hoverFillFor(Colors.bar.text, Colors.bar.text) : "transparent"
          }

          MenuText {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: Style.space(22)
            horizontalAlignment: Text.AlignHCenter
            text: "<"
          }

          MenuText {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(28)
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.md
            text: root.currentTitle
            elide: Text.ElideRight
          }

          MouseArea {
            id: backMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.menuLevelSettling) return
              trayMenuFlick.contentY = 0
              root.leaveSubmenu()
            }
          }
        }

        Item {
          width: menuHeader.width
          implicitHeight: Style.space(11)

          Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: Colors.popups.border
            opacity: Style.emphasis.faint
          }
        }
      }

      Flickable {
        id: trayMenuFlick
        width: trayMenuLayout.width
        height: trayMenuLayout.height - trayMenuPopup.menuHeaderHeight
        contentWidth: width
        contentHeight: trayMenuColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: trayMenuColumn
          width: trayMenuFlick.width

          Repeater {
            model: root.currentChildren

            delegate: Item {
              id: menuRow
              required property var modelData
              required property int index

              readonly property string rowText: String(modelData.text || "")
              readonly property string activeTitle: root.activeTrayItem ? String(root.activeTrayItem.title || root.activeTrayItem.id || "") : ""
              readonly property bool atRoot: root.submenuDepth === 0
              readonly property bool rootTitleEntry: atRoot && index === 0 && modelData.hasChildren && rowText.toLowerCase() === activeTitle.toLowerCase()
              readonly property bool leadingSeparator: atRoot && modelData.isSeparator && index <= 1
              readonly property bool hiddenRow: rootTitleEntry || leadingSeparator

              function activate() {
                if (root.menuLevelSettling) return
                if (menuRow.modelData.hasChildren) {
                  trayMenuFlick.contentY = 0
                  root.enterSubmenu(menuRow.modelData, menuRow.rowText)
                } else {
                  menuRow.modelData.triggered()
                  root.close()
                }
              }

              visible: !hiddenRow
              activeFocusOnTab: !hiddenRow && !modelData.isSeparator && modelData.enabled
              Keys.onReturnPressed: menuRow.activate()
              Keys.onEnterPressed: menuRow.activate()
              Keys.onSpacePressed: menuRow.activate()
              Keys.onPressed: function(event) {
                if ((event.key === Qt.Key_Left || event.text === "h") && root.submenuDepth > 0) {
                  root.leaveSubmenu()
                  event.accepted = true
                }
              }
              width: trayMenuColumn.width
              implicitHeight: hiddenRow ? 0 : (modelData.isSeparator ? Style.space(9) : Style.space(26))
              opacity: modelData.enabled ? 1 : Style.emphasis.faint

              Rectangle {
                visible: menuRow.modelData.isSeparator
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.md
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Colors.popups.border
                opacity: Style.emphasis.faint
              }

              Rectangle {
                visible: !menuRow.modelData.isSeparator
                anchors.fill: parent
                radius: Style.shape.data
                color: (rowMouse.containsMouse || menuRow.activeFocus) && menuRow.modelData.enabled ? Style.hoverFillFor(Colors.bar.text, Colors.bar.text) : "transparent"
              }

              MenuText {
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.buttonType !== QsMenuButtonType.None
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                width: Style.space(22)
                horizontalAlignment: Text.AlignHCenter
                text: menuRow.modelData.checkState === Qt.Checked ? "\uf00c" : ""
              }

              MenuText {
                visible: !menuRow.modelData.isSeparator && rowMouse.containsMouse && menuRow.modelData.buttonType === QsMenuButtonType.None
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                width: trayMenuPopup.checkGutter
                horizontalAlignment: Text.AlignHCenter
                text: ">"
                color: Colors.textDim
              }

              Image {
                visible: !menuRow.modelData.isSeparator && String(menuRow.modelData.icon || "") !== ""
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: trayMenuPopup.checkGutter
                width: Style.space(16)
                height: Style.space(16)
                fillMode: Image.PreserveAspectFit
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: menuRow.modelData.icon
              }

              MenuText {
                visible: !menuRow.modelData.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: trayMenuPopup.textInset
                anchors.right: submenuGlyph.left
                anchors.rightMargin: Style.spacing.sm
                text: menuRow.rowText
                elide: Text.ElideRight
              }

              MenuText {
                id: submenuGlyph
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.hasChildren
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                text: ">"
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !menuRow.modelData.isSeparator && menuRow.modelData.enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: menuRow.activate()
              }
            }
          }
        }
      }
    }
  }

  component MenuText: Label {
    color: Colors.bar.text
    font.pixelSize: Style.font.bodySmall
  }

  component TrayIcon: Item {
    id: trayIconRoot
    required property var icon
    readonly property bool symbolic: root.iconIsSymbolic(icon)

    Image {
      id: trayIconImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      source: String(trayIconRoot.icon || "")
      visible: !trayIconRoot.symbolic
    }

    MultiEffect {
      anchors.fill: trayIconImage
      source: trayIconImage
      visible: trayIconRoot.symbolic
      colorization: 1.0
      colorizationColor: Colors.bar.text
    }
  }

  component TrayItem: Item {
    id: trayItemRoot

    required property var modelData

    visible: modelData.status !== Status.Passive
    implicitWidth: visible ? root.trayItemExtent : 0
    implicitHeight: visible ? root.trayItemExtent : 0

    function displayMenu(mouse) {
      root.openTrayMenu(trayItemRoot.modelData, trayItemRoot, mouse)
    }

    Rectangle {
      anchors.centerIn: parent
      width: parent.width
      height: Style.bar.sizeHorizontal
      radius: Style.shape.data
      color: trayMouse.pressed ? Style.pressedFill : trayMouse.containsMouse ? Style.hoverFill : "transparent"
      Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
    }

    TrayIcon {
      anchors.centerIn: parent
      width: Style.bar.iconCanvas
      height: Style.bar.iconCanvas
      icon: trayItemRoot.modelData.icon
    }

    MouseArea {
      id: trayMouse
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(trayItemRoot, root.trayTooltip(trayItemRoot.modelData))
      onExited: if (root.bar) root.bar.hideTooltip(trayItemRoot)
      onPressed: function(mouse) {
        if (mouse.button === Qt.RightButton && (mouse.modifiers & Qt.ShiftModifier)) {
          root.managePopupOpen = !root.managePopupOpen
          mouse.accepted = true
        } else if (mouse.button === Qt.RightButton) {
          trayItemRoot.displayMenu(mouse)
          mouse.accepted = true
        }
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          mouse.accepted = true
        } else if (mouse.button === Qt.MiddleButton) {
          trayItemRoot.modelData.secondaryActivate()
        } else {
          root.activateItem(trayItemRoot.modelData, trayItemRoot, mouse)
        }
      }
      onWheel: function(wheel) {
        trayItemRoot.modelData.scroll(wheel.angleDelta.y, false)
      }
    }
  }
}
