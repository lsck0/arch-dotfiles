import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons

PopupWindow {
  id: root

  required property Item anchorItem
  required property var bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.surface.padding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property bool open: false

  readonly property bool docked: bar !== null
  readonly property real neckWidth: docked ? Style.shape.neck * 2 : 0

  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property var popupScreen: anchorWindow ? anchorWindow.screen : null
  readonly property real screenW: popupScreen ? popupScreen.width : 0
  readonly property real screenH: popupScreen ? popupScreen.height : 0
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  readonly property real availableCardWidth: screenW > 0
    ? Math.max(Style.space(120), screenW - root.margin * 2 - root.neckWidth)
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(Style.space(120), screenH - barH - root.margin * 2)
    : 0
  readonly property real verticalContentInset: (padding + Style.surface.borderWidth) * 2

  readonly property real slideDistance: Style.space(14)
  readonly property real revealSlide: !docked ? 0
    : -(1 - boot.progress) * slideDistance

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

  default property alias body: contentHolder.children

  visible: open || boot.progress > 0
  color: "transparent"
  implicitWidth: contentWidth + neckWidth
  implicitHeight: contentHeight

  HyprlandFocusGrab {
    active: root.open
    windows: root.anchorWindow ? [root, root.anchorWindow] : [root]
    onCleared: root.close()
  }

  anchor {
    window: root.anchorWindow // qmllint disable missing-property
    adjustment: PopupAdjustment.Slide // qmllint disable missing-property
    edges: Edges.Top | Edges.Left // qmllint disable missing-property
    gravity: Edges.Bottom | Edges.Right // qmllint disable missing-property
    rect.width: 1 // qmllint disable unqualified unresolved-type
    rect.height: 1 // qmllint disable unqualified unresolved-type

    onAnchoring: { // qmllint disable unqualified
      if (!root.anchorItem || !root.bar) return

      var target = root.anchorItem
      var window = target.QsWindow.window
      if (!window) return
      var popupWidth = root.implicitWidth
      var point = window.contentItem.mapFromItem(target, target.width / 2 - popupWidth / 2, 0) // qmllint disable missing-property
      root.anchor.rect.x = Math.round(Math.max(root.margin, Math.min(point.x, window.width - popupWidth - root.margin))) // qmllint disable missing-property
      root.anchor.rect.y = window.height // qmllint disable missing-property
    }
  }

  BootIn {
    id: boot
    active: root.open
    span: Math.min(card.width, card.height) / 2
  }

  function focusWalk(forward) {
    var next = (keys.Window.activeFocusItem || keys).nextItemInFocusChain(forward)
    if (next) next.forceActiveFocus()
  }

  onOpenChanged: if (open) keys.forceActiveFocus()

  // Esc closes, Tab and hjkl walk the focusable rows, like a HoverPanel
  PanelKeyCatcher {
    id: keys
    anchors.fill: parent
    blocked: !root.open
    onCloseRequested: root.close()
    onTabRequested: function(direction) { root.focusWalk(direction > 0) }
    onMoveRequested: function(dx, dy) { root.focusWalk(dy > 0 || dx > 0) }

    Item {
      id: reveal
      width: parent.width
      height: Math.round(parent.height * boot.progress)
      clip: true
      opacity: boot.progress
      transform: Translate { y: root.revealSlide }

      DockShape {
        id: card
        width: root.width
        height: root.height
        docked: root.docked
        fillColor: Colors.menu.background
      }

      Item {
        id: contentHolder
        x: card.sideInset + card.strokeWidth + root.padding
        y: card.strokeWidth + root.padding
        width: card.width - x * 2
        height: card.height - (card.strokeWidth + root.padding) * 2
        opacity: boot.rowOpacity(1)
      }

      Item {
        x: card.sideInset
        width: card.width - card.sideInset * 2
        height: card.height
        HudFrame { inset: boot.bracketInset; chamfer: card.cut; chamferCorner: card.cutCorner }
      }
    }
  }
}
