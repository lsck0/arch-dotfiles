import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons

// bar popup (tray menus): docked to the bar rule like HoverPanel when the bar is top or bottom
PopupWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.surface.padding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property bool open: false

  readonly property bool docked: bar !== null && (bar.position === "top" || bar.position === "bottom")
  // the neck flare widens the window, contentWidth stays the card's own width
  readonly property real neckWidth: docked ? Style.shape.neck * 2 : 0

  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property var popupScreen: anchorWindow ? anchorWindow.screen : null
  readonly property real screenW: popupScreen ? popupScreen.width : 0
  readonly property real screenH: popupScreen ? popupScreen.height : 0
  readonly property real barW: anchorWindow ? anchorWindow.width : 0
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((bar && (bar.position === "left" || bar.position === "right")) ? barW : 0) - root.margin * 2 - root.neckWidth)
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((bar && (bar.position === "top" || bar.position === "bottom")) ? barH : 0) - root.margin * 2)
    : 0
  readonly property real verticalContentInset: (padding + Style.surface.borderWidth) * 2

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0) maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0) maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  default property alias contentItem: contentHolder.children

  // mapped until the fold-back ends
  visible: open || boot.progress > 0
  color: "transparent"
  implicitWidth: contentWidth + neckWidth
  implicitHeight: contentHeight

  // click outside dismisses
  HyprlandFocusGrab {
    active: root.open
    windows: root.anchorWindow ? [root, root.anchorWindow] : [root]
    onCleared: root.close()
  }

  anchor {
    id: popupAnchor
    window: root.anchorWindow
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      if (!root.anchorItem || !root.bar) return

      var target = root.anchorItem
      var window = target.QsWindow.window
      if (!window) return
      var popupWidth = root.implicitWidth
      var popupHeight = root.implicitHeight
      var localX = target.width / 2 - popupWidth / 2
      var localY = target.height + root.margin

      if (root.bar.position === "bottom") {
        localY = -popupHeight - root.margin
      } else if (root.bar.position === "left") {
        localX = target.width + root.margin
        localY = target.height / 2 - popupHeight / 2
      } else if (root.bar.position === "right") {
        localX = -popupWidth - root.margin
        localY = target.height / 2 - popupHeight / 2
      }

      var point = window.contentItem.mapFromItem(target, localX, localY)
      // docked: flush with the bar window's edge, so the neck meets the accent rule
      if (root.bar.position === "top") point.y = window.height
      else if (root.bar.position === "bottom") point.y = -popupHeight

      if (root.bar.position === "top" || root.bar.position === "bottom") {
        point.x = Math.max(root.margin, Math.min(point.x, window.width - popupWidth - root.margin))
      } else {
        point.y = Math.max(root.margin, Math.min(point.y, window.height - popupHeight - root.margin))
      }

      popupAnchor.rect.x = Math.round(point.x)
      popupAnchor.rect.y = Math.round(point.y)
    }
  }

  BootIn {
    id: boot
    active: root.open
    span: Math.min(card.width, card.height) / 2
  }

  Item {
    id: reveal
    width: parent.width
    height: Math.round(parent.height * boot.progress)
    // a bottom bar grows the drawer upward
    y: root.bar && root.bar.position === "bottom" ? parent.height - height : 0
    clip: true

    DockShape {
      id: card
      y: -reveal.y
      width: root.width
      height: root.height
      docked: root.docked
      flipped: root.bar !== null && root.bar.position === "bottom"
      fillColor: Color.menu.background
    }

    Item {
      id: contentHolder
      x: card.sideInset + card.strokeWidth + root.padding
      y: card.y + card.strokeWidth + root.padding
      width: card.width - x * 2
      height: card.height - (card.strokeWidth + root.padding) * 2
      opacity: boot.rowOpacity(1)
    }

    Item {
      x: card.sideInset
      y: card.y
      width: card.width - card.sideInset * 2
      height: card.height
      HudFrame { inset: boot.bracketInset }
    }
  }
}
