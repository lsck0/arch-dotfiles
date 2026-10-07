import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Ui
import "TrayModel.js" as TrayModel

BarWidget {
  id: root
  moduleName: "tray"

  property bool managePopupOpen: false
  property bool trayMenuOpen: false
  property var activeTrayItem: null
  property var activeTrayAnchor: null
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var pinnedIds: settings.pinned instanceof Array ? settings.pinned : []
  readonly property var hiddenIds: settings.hidden instanceof Array ? settings.hidden : []
  readonly property var pinnedItems: bucket("pinned")
  readonly property var drawerItems: bucket("drawer")
  readonly property var allItems: bucket("all")
  readonly property int drawerCount: drawerItems.length
  readonly property int trayItemExtent: Style.bar.iconSlot
  readonly property int trayItemGap: Style.bar.itemGap
  readonly property int trayJoinGap: Style.bar.groupGap
  readonly property int drawerExtent: drawerCount > 0 ? drawerCount * trayItemExtent + (drawerCount - 1) * trayItemGap : 0

  property var submenuStack: []
  readonly property int submenuDepth: submenuStack.length
  readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
  readonly property var currentChildren: submenuDepth > 0
    ? submenuStack[submenuDepth - 1].opener.children
    : trayMenuOpener.children

  // swallows the click that lands on the rebuilt level
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
    // flickable keeps its offset across a model swap
    trayMenuFlick.contentY = 0
    // clear the stack before destroying, so no binding reads a dead opener
    var openers = submenuStack
    submenuStack = []
    for (var i = openers.length - 1; i >= 0; i--) openers[i].opener.destroy()
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
      var point = anchorItem.QsWindow.contentItem.mapFromItem(anchorItem, mouse.x, mouse.y)
      item.display(anchorItem.QsWindow.window, point.x, point.y)
      return
    }

    // reset first: a new item invalidates the old children at once
    resetTrayMenu()
    activeTrayItem = item
    activeTrayAnchor = anchorItem
    trayMenuOpen = true
  }

  // symbolic icons are meant to be recoloured by the host
  function iconIsSymbolic(icon) {
    var name = String(icon || "").split("?")[0]
    return name.slice(-9) === "-symbolic"
  }

  function trayTooltip(item) {
    return item.tooltipTitle || item.title || item.id || ""
  }

  function classifyItem(item) {
    var iid = String(item.id || "")
    if (hiddenIds.indexOf(iid) !== -1) return "hidden"
    if (pinnedIds.indexOf(iid) !== -1) return "pinned"
    return "drawer"
  }

  function bucket(category) {
    var values = SystemTray.items.values
    var result = []
    for (var i = 0; i < values.length; i++) {
      var item = values[i]
      if (item.status === Status.Passive) continue
      if (TrayModel.hiddenByDefault(item)) continue
      if (category === "all") {
        result.push(item)
        continue
      }
      if (classifyItem(item) === category) result.push(item)
    }
    return result
  }

  // widget-settings.json, keyed by widget name
  function persistTrayState(pinned, hidden) {
    if (!root.bar || !root.bar.shellHost || typeof root.bar.shellHost.setWidgetSettings !== "function") return
    root.bar.shellHost.setWidgetSettings("Tray", { pinned: pinned, hidden: hidden })
  }

  function togglePin(iid) {
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    var idx = p.indexOf(iid)
    if (idx !== -1) p.splice(idx, 1)
    else {
      p.push(iid)
      var hi = h.indexOf(iid)
      if (hi !== -1) h.splice(hi, 1)
    }
    persistTrayState(p, h)
  }

  function toggleHide(iid) {
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    var idx = h.indexOf(iid)
    if (idx !== -1) h.splice(idx, 1)
    else {
      h.push(iid)
      var pi = p.indexOf(iid)
      if (pi !== -1) p.splice(pi, 1)
    }
    persistTrayState(p, h)
  }

  visible: pinnedItems.length > 0 || drawerCount > 0
  clip: false
  implicitWidth: root.vertical ? root.barSize : trayContent.implicitWidth
  implicitHeight: root.vertical ? trayContent.implicitHeight : root.barSize

  Loader {
    id: trayContent
    anchors.fill: parent
    sourceComponent: root.vertical ? verticalTray : horizontalTray
  }

  Component {
    id: horizontalTray

    Item {
      id: horizontalTrayRoot

      readonly property int pinnedWidth: pinnedRow.implicitWidth

      implicitWidth: pinnedWidth + root.drawerExtent
      implicitHeight: root.barSize

      containmentMask: QtObject {
        function contains(point: point): bool {
          if (point.y < 0 || point.y > horizontalTrayRoot.height) return false
          return point.x >= 0 && point.x <= horizontalTrayRoot.implicitWidth
        }
      }

      Item {
        width: root.drawerExtent
        height: root.barSize
        visible: root.allItems.length > 0

        // right-click on empty space opens the manage popup
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
          height: root.barSize
          clip: true

          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.trayItemGap
            // no layer: it ate clicks meant for the delegates

            Repeater {
              model: root.drawerItems
              TrayItem {}
            }
          }
        }
      }

      Row {
        id: pinnedRow
        x: root.drawerExtent
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.trayItemGap
        leftPadding: root.pinnedItems.length > 0 && root.drawerCount > 0 ? root.trayJoinGap : 0
        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
      }
    }
  }

  Component {
    id: verticalTray

    Item {
      id: verticalTrayRoot

      readonly property int pinnedHeight: pinnedCol.implicitHeight

      implicitWidth: root.barSize
      implicitHeight: pinnedHeight + root.drawerExtent

      containmentMask: QtObject {
        function contains(point: point): bool {
          if (point.x < 0 || point.x > verticalTrayRoot.width) return false
          return point.y >= 0 && point.y <= verticalTrayRoot.implicitHeight
        }
      }

      Item {
        width: root.barSize
        height: root.drawerExtent
        visible: root.allItems.length > 0

        // declared first so it sits under the icons
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.RightButton
          onPressed: function(mouse) {
            if (mouse.button === Qt.RightButton) root.managePopupOpen = !root.managePopupOpen
          }
        }

        Item {
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.barSize
          height: root.drawerExtent
          clip: true

          Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.trayItemGap

            Repeater {
              model: root.drawerItems
              TrayItem {}
            }
          }
        }
      }

      Column {
        id: pinnedCol
        y: root.drawerExtent
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.trayItemGap
        topPadding: root.pinnedItems.length > 0 && root.drawerCount > 0 ? root.trayJoinGap : 0
        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
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

      Text {
        text: "Tray icons"
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Style.headerTracking
      }

      Text {
        text: "Pinned icons stay visible. Hidden icons never show."
        color: root.foreground
        opacity: Style.emphasis.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Text {
        visible: root.allItems.length === 0
        text: "No tray items reporting."
        color: root.foreground
        opacity: Style.emphasis.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.italic: true
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
          readonly property bool isPinned: root.pinnedIds.indexOf(itemId) !== -1
          readonly property bool isHidden: root.hiddenIds.indexOf(itemId) !== -1

          TrayIcon {
            id: rowIcon
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: Style.bar.iconCanvas
            height: Style.bar.iconCanvas
            icon: rowRoot.modelData.icon
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: rowIcon.right
            anchors.leftMargin: Style.spacing.md
            anchors.right: rowHideBtn.left
            anchors.rightMargin: Style.spacing.sm
            text: rowRoot.displayName
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Button {
            id: rowPinBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            iconText: "\uf08d"
            text: rowRoot.isPinned ? "Unpin" : "Pin"
            foreground: root.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            iconSize: Style.font.bodySmall
            fontSize: Style.font.bodySmall
            onClicked: root.togglePin(rowRoot.itemId)
          }

          Button {
            id: rowHideBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: rowPinBtn.left
            anchors.rightMargin: Style.spacing.sm
            iconText: "\uf06e"
            text: rowRoot.isHidden ? "Show" : "Hide"
            foreground: root.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
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
    // on visible, not open: resetting mid-fade flashes the root menu
    onVisibleChanged: if (!visible) root.resetTrayMenu()
    contentWidth: trayMenuPopup.fittedContentWidth(Style.space(232))
    contentHeight: trayMenuPopup.fittedContentHeight(menuHeaderHeight + trayMenuColumn.implicitHeight, Style.space(420))

    // Column still reports hidden children's height
    readonly property int menuHeaderHeight: menuHeader.visible ? menuHeader.implicitHeight : 0
    readonly property var menuEntries: root.currentChildren ? root.currentChildren.values : []
    readonly property bool hasCheckColumn: menuEntries.some(e => !e.isSeparator && e.buttonType !== QsMenuButtonType.None)
    readonly property bool hasIconColumn: menuEntries.some(e => !e.isSeparator && String(e.icon || "") !== "")
    readonly property int checkGutter: hasCheckColumn ? Style.space(22) : Style.space(8)
    readonly property int textInset: checkGutter + (hasIconColumn ? Style.space(22) : 0)

    Column {
      id: trayMenuLayout
      anchors.fill: parent
      spacing: 0

      Column {
        id: menuHeader
        visible: root.submenuDepth > 0
        width: trayMenuLayout.width
        spacing: 0

        Item {
          width: menuHeader.width
          implicitHeight: Style.space(30)

          Rectangle {
            anchors.fill: parent
            radius: Style.shape.data
            color: backMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: Style.space(22)
            horizontalAlignment: Text.AlignHCenter
            text: "\u2039"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(28)
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.md
            text: root.currentTitle
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
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
            color: Color.popups.border
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
          spacing: 0

          Repeater {
            model: root.currentChildren

            delegate: Item {
              id: menuRow
              required property var modelData
              required property int index

              readonly property string rowText: String(modelData.text || "")
              readonly property string activeTitle: root.activeTrayItem ? String(root.activeTrayItem.title || root.activeTrayItem.id || "") : ""
              // title row and leading separator exist only at the root
              readonly property bool atRoot: root.submenuDepth === 0
              readonly property bool rootTitleEntry: atRoot && index === 0 && modelData.hasChildren && rowText.toLowerCase() === activeTitle.toLowerCase()
              readonly property bool leadingSeparator: atRoot && modelData.isSeparator && index <= 1
              readonly property bool hiddenRow: rootTitleEntry || leadingSeparator

              visible: !hiddenRow
              width: trayMenuColumn.width
              implicitHeight: hiddenRow ? 0 : (modelData.isSeparator ? Style.space(9) : Style.space(26))
              opacity: modelData.enabled ? 1.0 : 0.45

              Rectangle {
                visible: menuRow.modelData.isSeparator
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.md
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Color.popups.border
                opacity: Style.emphasis.faint
              }

              Rectangle {
                visible: !menuRow.modelData.isSeparator
                anchors.fill: parent
                radius: Style.shape.data
                color: rowMouse.containsMouse && menuRow.modelData.enabled ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
              }

              Text {
                textFormat: Text.PlainText
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.buttonType !== QsMenuButtonType.None
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                width: Style.space(22)
                horizontalAlignment: Text.AlignHCenter
                text: menuRow.modelData.checkState === Qt.Checked ? "\uf00c" : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Image {
                visible: !menuRow.modelData.isSeparator && String(menuRow.modelData.icon || "") !== ""
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: trayMenuPopup.checkGutter
                width: Style.space(16)
                height: Style.space(16)
                fillMode: Image.PreserveAspectFit
                // decode at physical pixels for hidpi
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: menuRow.modelData.icon
              }

              Text {
                textFormat: Text.PlainText
                visible: !menuRow.modelData.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: trayMenuPopup.textInset
                anchors.right: submenuGlyph.left
                anchors.rightMargin: Style.spacing.sm
                text: menuRow.rowText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                id: submenuGlyph
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.hasChildren
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                text: "\u203a"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !menuRow.modelData.isSeparator && menuRow.modelData.enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.menuLevelSettling) return
                  if (menuRow.modelData.hasChildren) {
                    // before the swap: it destroys this delegate
                    trayMenuFlick.contentY = 0
                    root.enterSubmenu(menuRow.modelData, menuRow.rowText)
                  } else {
                    menuRow.modelData.triggered()
                    root.close()
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component TrayIcon: Item {
    id: trayIconRoot
    required property var icon
    readonly property bool symbolic: root.iconIsSymbolic(icon)

    Image {
      id: trayIconImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      // decode at physical pixels for hidpi
      sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      // quickshell already resolves this to an image:// url
      source: String(trayIconRoot.icon || "")
      // texture source for the MultiEffect only
      visible: false
      layer.enabled: Style.fx.glow > 0
    }

    MultiEffect {
      anchors.fill: trayIconImage
      source: trayIconImage
      visible: true
      colorization: trayIconRoot.symbolic ? 1.0 : 0.85
      colorizationColor: root.foreground
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

    TrayIcon {
      anchors.centerIn: parent
      width: Style.bar.iconCanvas
      height: Style.bar.iconCanvas
      icon: trayItemRoot.modelData.icon
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(trayItemRoot, root.trayTooltip(modelData))
      onExited: if (root.bar) root.bar.hideTooltip(trayItemRoot)
      onPressed: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          trayItemRoot.displayMenu(mouse)
          mouse.accepted = true
        }
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          mouse.accepted = true
        } else if (mouse.button === Qt.MiddleButton) {
          trayItemRoot.modelData.secondaryActivate()
        } else if (trayItemRoot.modelData.onlyMenu) {
          trayItemRoot.displayMenu(mouse)
        } else {
          trayItemRoot.modelData.activate()
        }
      }
      onWheel: function(wheel) {
        trayItemRoot.modelData.scroll(wheel.angleDelta.y, false)
      }
    }
  }
}
