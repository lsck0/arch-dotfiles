import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// docked drawer under the bar (signature A): grows out of the bar's accent rule, reports hover to the bar.
// Keys once it has focus (click, or hyprland's on-demand focus): Esc closes, Tab / arrows / hjkl walk
// the focusable controls, Enter / Space activate them; a focused text input pins the drawer open.
PanelWindow {
  id: root

  property QtObject bar: null
  property string moduleName: ""
  property real padding: Style.surface.padding
  property string title: ""
  // add to implicitHeight
  readonly property real titleInset: titleBar.visible ? titleBar.height + Style.spacing.sm : 0
  default property alias data: inner.data

  // opens centred under this bar widget
  property Item anchorWidget: null
  readonly property bool anchored: anchorWidget !== null

  readonly property real edgeMargin: Style.spacing.sm
  // tallest body that fits under the bar; taller content scrolls (Flickable in the panel)
  readonly property real maxBodyHeight: Math.max(Style.space(120),
    (screen ? screen.height : Style.space(1080)) - Style.bar.sizeHorizontal - Style.gapsOut * 2 - padding * 2 - titleInset)

  readonly property real anchoredLeft: {
    if (!anchored || !bar) return 0
    var centre = anchorWidget.barX + anchorWidget.width / 2
    var maxLeft = Math.max(edgeMargin, bar.width - implicitWidth - edgeMargin)
    return Math.max(edgeMargin, Math.min(maxLeft, centre - implicitWidth / 2))
  }

  signal opened()

  // window stays mapped until the drawer has folded back
  readonly property bool shown: bar !== null && bar.activePanel === moduleName
  // content reads it for its own row stagger: boot.rowOpacity(i)
  readonly property alias boot: boot

  visible: shown || boot.progress > 0
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
  margins {
    // docked: the exclusive zone already starts right below the bar rule
    top: 0
    left: root.anchored ? root.anchoredLeft : 0
    right: root.anchored ? 0 : Style.spacing.sm
  }

  // hyprland_windowrules.lua blurs quickshell-panel-*
  WlrLayershell.namespace: "quickshell-panel-" + (moduleName || "panel")
  WlrLayershell.layer: WlrLayer.Overlay
  // on-demand: never steals the keyboard, takes it when the pointer clicks in
  property bool acceptsKeyboard: true
  // extra pin from the owner; a focused text input pins on its own
  property bool pinned: false
  readonly property bool textFocused: {
    var f = keys.Window.activeFocusItem
    return !!f && f.cursorPosition !== undefined && f.selectByMouse !== undefined
  }
  // pointer exits do not close the panel while held
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
    id: boot
    active: root.shown
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

    // grows from the bar downward; the drawer itself never resizes
    Item {
      id: reveal
      width: parent.width
      height: Math.round(parent.height * boot.progress)
      clip: true

      DockShape {
        id: card
        width: root.width
        height: root.height
        docked: true
        flipped: root.bar !== null && root.bar.position === "bottom"
        fillColor: Color.menu.background

        readonly property real contentLeftInset: sideInset + strokeWidth + root.padding
        readonly property real contentRightInset: contentLeftInset
        readonly property real contentTopInset: root.padding
        readonly property real contentBottomInset: strokeWidth + root.padding
      }

      // brackets frame the body, not the neck flare
      Item {
        x: card.sideInset
        width: card.width - card.sideInset * 2
        height: card.height
        HudFrame { inset: boot.bracketInset }
      }

      Item {
        id: inner
        x: card.contentLeftInset
        y: card.contentTopInset + root.titleInset
        width: card.width - card.contentLeftInset - card.contentRightInset
        height: card.height - card.contentTopInset - card.contentBottomInset - root.titleInset
        opacity: boot.rowOpacity(1)
      }

      HudTitle {
        id: titleBar
        visible: root.title.length > 0
        z: 4
        x: card.contentLeftInset
        y: card.contentTopInset
        width: card.width - card.contentLeftInset - card.contentRightInset
        height: visible ? implicitHeight : 0
        text: root.title
        typed: boot.typed
        decor: true
        rule: true
        blinking: visible && root.shown
      }

      // sized to the drawer, not the growing clip, so it paints once
      Scanlines { anchors.fill: card; shown: root.shown; flicker: true }
    }
  }
}
