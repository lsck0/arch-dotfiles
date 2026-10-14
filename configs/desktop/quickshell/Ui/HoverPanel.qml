import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// keys once focused (click or hyprland on-demand focus); a focused text input pins it open
PanelWindow {
  id: root

  // untyped: Ui cannot import plugins/bar back
  property var bar: null
  property string moduleName: ""
  property real padding: Style.surface.padding
  property string title: ""
  // callers add this to implicitHeight
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

  // window stays mapped until the drawer has folded back
  readonly property bool shown: bar !== null && bar.activePanel === moduleName
  readonly property alias boot: bootIn

  visible: shown || bootIn.progress > 0
  onShownChanged: {
    if (!shown) return
    if (anchorWidget && anchorWidget.refreshBarX) anchorWidget.refreshBarX()
    keys.forceActiveFocus()
    opened()
  }

  screen: bar && bar.screen ? bar.screen : null
  color: "transparent"

  // layer-shell has no free x, offset from one anchored edge
  anchors {
    top: true
    left: root.anchored
    right: !root.anchored
  }
  // quickshell's qmltypes stub Margins as opaque, so qmllint cannot see its edges
  margins {
    // the exclusive zone already starts below the bar rule
    top: 0 // qmllint disable missing-property
    left: root.anchored ? root.anchoredLeft : 0 // qmllint disable missing-property
    right: root.anchored ? 0 : Style.spacing.sm // qmllint disable missing-property
  }

  // hyprland_windowrules.lua blurs quickshell-panel-*
  WlrLayershell.namespace: "quickshell-panel-" + (moduleName || "panel")
  WlrLayershell.layer: WlrLayer.Overlay
  // on-demand: never steals the keyboard, takes it when the pointer clicks in
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

  HoverHandler {
    id: hover
    onHoveredChanged: {
      if (!root.bar) return
      if (hovered) root.bar.hoverPanelEnter(root.moduleName)
      else if (!root.held) root.bar.hoverPanelExit(root.moduleName)
    }
  }

  // walks the window's tab chain, which only holds this drawer's controls
  function walkFocus(forward) {
    var from = keys.Window.activeFocusItem || keys
    var next = from.nextItemInFocusChain(forward)
    if (next && next !== from) next.forceActiveFocus()
  }

  BootIn {
    id: bootIn
    active: root.shown
    // snaps so a switch reads as one drawer moving, not a close-reopen
    instant: root.bar !== null && root.bar.panelSwitching
    title: root.title
    span: Math.min(card.width, card.height) / 2
  }

  // ancestor of every control: sees only the keys they leave unaccepted
  PanelKeyCatcher {
    id: keys
    anchors.fill: parent
    blocked: !root.shown
    onCloseRequested: if (root.bar) root.bar.closePanel(root.moduleName)
    onTabRequested: function(direction) { root.walkFocus(direction > 0) }
    onMoveRequested: function(dx, dy) { root.walkFocus(dx + dy > 0) }

    // the clip grows on boot.progress, the card never resizes
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

      // brackets frame the body, not the neck flare
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

      // sized to the drawer, not the growing clip, so it paints once
      Scanlines { anchors.fill: card; shown: root.shown; flicker: true }
    }
  }
}
