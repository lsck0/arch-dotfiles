import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons

PanelWindow {
  id: root

  // untyped: Ui cannot import plugins/bar back
  property var bar: null
  property string moduleName: ""
  property real padding: Style.surface.padding
  property string title: ""
  readonly property real titleInset: titleBar.visible ? titleBar.height + Style.spacing.sm : 0
  default property alias body: inner.data

  property BarWidget anchorWidget: null
  readonly property bool anchored: anchorWidget !== null

  readonly property real edgeMargin: Style.spacing.sm

  // quickshell's qmltypes stub the screen type as opaque, so qmllint cannot see its height
  readonly property real maxBodyHeight: Math.max(Style.space(120),
    (screen ? screen.height : Style.space(1080)) - Style.bar.sizeHorizontal - Style.gapsOut * 2 - padding * 2 - titleInset) // qmllint disable missing-property

  readonly property real anchoredLeft: {
    if (!anchored || !bar) return 0
    var centre = anchorWidget.barX + anchorWidget.width / 2
    var maxLeft = Math.max(edgeMargin, bar.width - implicitWidth - edgeMargin)
    return Math.max(edgeMargin, Math.min(maxLeft, centre - implicitWidth / 2))
  }

  signal opened()

  readonly property bool shown: bar !== null && bar.activePanel === moduleName
  readonly property alias boot: bootIn

  visible: shown || bootIn.progress > 0
  onShownChanged: {
    root.clicked = false
    if (!shown) return
    // a hover open passes through Bar.hoverOpen, which leaves the pending id behind; ipc and keybinds do not
    root.hoverOpened = !!bar && bar.pendingPanel === moduleName
    if (anchorWidget && anchorWidget.refreshBarX) anchorWidget.refreshBarX()
    keys.forceActiveFocus()
    opened()
  }

  screen: bar && bar.screen ? bar.screen : null
  color: "transparent"

  anchors {
    top: true
    left: root.anchored
    right: !root.anchored
  }
  // quickshell's qmltypes stub Margins as opaque, so qmllint cannot see its edges
  margins {
    top: 0 // qmllint disable missing-property
    left: root.anchored ? root.anchoredLeft : 0 // qmllint disable missing-property
    right: root.anchored ? 0 : Style.spacing.sm // qmllint disable missing-property
  }

  // hyprland_windowrules.lua blurs quickshell-panel-*
  WlrLayershell.namespace: "quickshell-panel-" + (moduleName || "panel")
  WlrLayershell.layer: WlrLayer.Overlay
  property bool acceptsKeyboard: true
  property bool pinned: false
  readonly property bool textFocused: {
    var f = keys.Window.activeFocusItem
    return !!f && "cursorPosition" in f && "selectByMouse" in f
  }
  readonly property bool held: pinned || textFocused
  onHeldChanged: if (!held && !hover.hovered && bar) bar.hoverPanelExit(moduleName)
  WlrLayershell.keyboardFocus: root.acceptsKeyboard && root.shown
    ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  property bool hoverOpened: false
  property bool clicked: false

  // the grab keeps the pointer on the bar and this drawer, so a hover-out no longer reaches it: only outside clicks close
  HyprlandFocusGrab {
    active: root.shown && (root.held || root.clicked || !root.hoverOpened)
    windows: root.bar ? [root, root.bar] : [root]
    onCleared: if (root.bar) root.bar.closePanel(root.moduleName)
  }

  HoverHandler {
    id: hover
    onHoveredChanged: {
      if (!root.bar) return
      if (hovered) root.bar.hoverPanelEnter(root.moduleName)
      else if (!root.held) root.bar.hoverPanelExit(root.moduleName)
    }
  }

  function walkFocus(forward) {
    var from = keys.Window.activeFocusItem || keys
    var next = from.nextItemInFocusChain(forward)
    if (next && next !== from) next.forceActiveFocus()
  }

  BootIn {
    id: bootIn
    active: root.shown
    instant: root.bar !== null && root.bar.panelSwitching
    title: root.title
    span: Math.min(card.width, card.height) / 2
  }

  PanelKeyCatcher {
    id: keys
    anchors.fill: parent
    blocked: !root.shown
    onCloseRequested: if (root.bar) root.bar.closePanel(root.moduleName)
    onTabRequested: function(direction) { root.walkFocus(direction > 0) }
    onMoveRequested: function(dx, dy) { root.walkFocus(dx + dy > 0) }

    Item {
      id: reveal
      width: parent.width
      height: Math.round(parent.height * bootIn.progress)
      y: root.bar && root.bar.position === "bottom" ? parent.height - height : 0
      clip: true
      opacity: bootIn.progress

      DockShape {
        id: card
        y: -reveal.y
        width: root.width
        height: root.height
        docked: true
        neck: 0
        flipped: root.bar !== null && root.bar.position === "bottom"
        fillColor: Colors.bar.background

        readonly property real contentLeftInset: sideInset + strokeWidth + root.padding
        readonly property real contentRightInset: contentLeftInset
        readonly property real contentTopInset: root.padding
        readonly property real contentBottomInset: strokeWidth + root.padding
      }

      Item {
        x: card.sideInset
        y: card.y
        width: card.width - card.sideInset * 2
        height: card.height
        HudFrame { inset: bootIn.bracketInset; chamfer: card.cut; chamferCorner: card.cutCorner }
      }

      Item {
        id: inner
        x: card.contentLeftInset
        y: card.y + card.contentTopInset + root.titleInset
        width: card.width - card.contentLeftInset - card.contentRightInset
        height: card.height - card.contentTopInset - card.contentBottomInset - root.titleInset
        opacity: bootIn.rowOpacity(1)
      }

      HudTitle {
        id: titleBar
        visible: root.title.length > 0
        z: 4
        x: card.contentLeftInset
        y: card.y + card.contentTopInset
        width: card.width - card.contentLeftInset - card.contentRightInset
        height: visible ? implicitHeight : 0
        text: root.title
        typed: bootIn.typed
        decor: true
        rule: true
        blinking: visible && root.shown
      }

      Scanlines { anchors.fill: card; shown: root.shown; flicker: true }
    }

    // a focus grab that starts mid-press cancels the press (and a slider drag), so the grab waits for the release
    Item {
      anchors.fill: parent
      z: 1000
      PointHandler {
        acceptedButtons: Qt.AllButtons
        onActiveChanged: if (!active) root.clicked = true
      }
    }
  }
}
