import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons

PanelWindow {
  id: root

  // the widget it hangs off gives the bar and the panel's name
  property var bar: anchorWidget ? anchorWidget.bar : null
  property string moduleName: anchorWidget ? anchorWidget.moduleName : ""
  property real padding: Style.surface.padding
  property string title: ""
  readonly property real titleInset: titleBar.visible ? titleBar.height + Style.spacing.sm : 0
  default property alias body: inner.data

  property BarWidget anchorWidget: null
  readonly property bool anchored: anchorWidget !== null

  readonly property real edgeMargin: Style.spacing.sm

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
  readonly property bool keyboardOpened: shown && bar.keyboardPanel
  readonly property bool barPinned: shown && bar.pinnedPanel === moduleName

  readonly property bool panelRegistered: bar !== null && moduleName !== ""
  onPanelRegisteredChanged: if (panelRegistered) bar.panelRegister(moduleName)
  Component.onCompleted: if (panelRegistered) bar.panelRegister(moduleName)
  Component.onDestruction: if (panelRegistered) bar.panelUnregister(moduleName)

  readonly property alias boot: bootIn

  visible: shown || bootIn.progress > 0
  onShownChanged: {
    root.clicked = false
    if (!shown) return
    if (anchorWidget && anchorWidget.refreshBarX) anchorWidget.refreshBarX()
    keys.forceActiveFocus()
    opened()
  }

  readonly property bool windowActive: keys.Window.active
  onWindowActiveChanged: if (windowActive && keyboardOpened && keys.focus) walkFocus(true)
  onKeyboardOpenedChanged: if (windowActive && keyboardOpened && keys.focus) walkFocus(true)

  screen: bar && bar.screen ? bar.screen : null
  color: "transparent"

  anchors {
    top: true
    left: root.anchored
    right: !root.anchored
  }
  margins {
    top: 0 // qmllint disable missing-property
    left: root.anchored ? root.anchoredLeft : 0 // qmllint disable missing-property
    right: root.anchored ? 0 : Style.spacing.sm // qmllint disable missing-property
  }

  WlrLayershell.namespace: "quickshell-panel-" + (moduleName || "panel")
  WlrLayershell.layer: WlrLayer.Overlay
  property bool acceptsKeyboard: true
  property bool pinned: false
  readonly property bool textFocused: {
    var f = keys.Window.activeFocusItem
    return !!f && "cursorPosition" in f && "selectByMouse" in f
  }
  readonly property bool held: pinned || barPinned || textFocused
  onHeldChanged: if (!held && !hover.hovered && bar) bar.hoverPanelExit(moduleName)
  WlrLayershell.keyboardFocus: !root.acceptsKeyboard || !root.shown ? WlrKeyboardFocus.None
    : root.keyboardOpened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

  property bool clicked: false

  HyprlandFocusGrab {
    active: root.shown && (root.held || root.clicked)
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

  readonly property int focusChainMax: 512

  function itemInside(item) {
    for (let walk = item; walk; walk = walk.parent) if (walk === keys) return item !== keys
    return false
  }

  function itemY(item) { return item.mapToItem(keys, 0, 0).y }

  function focusChainItems() {
    let items = []
    let item = keys.nextItemInFocusChain(true)
    for (let step = 0; item && step < focusChainMax && items.indexOf(item) === -1; step++) {
      if (itemInside(item)) items.push(item)
      item = item.nextItemInFocusChain(true)
    }
    return items
  }

  function sectionHeaderYs(item, ys) {
    for (let i = 0; i < item.children.length; i++) {
      const child = item.children[i]
      if (!child.visible) continue
      if (child.panelSectionHeader === true) ys.push(itemY(child))
      else sectionHeaderYs(child, ys)
    }
    return ys
  }

  function sectionJump(forward) {
    const headers = sectionHeaderYs(inner, []).sort(function(a, b) { return a - b })
    const items = focusChainItems()
    if (items.length === 0) return
    if (headers.length === 0) { walkFocus(forward); return }
    function sectionOf(y) {
      let section = 0
      while (section < headers.length && headers[section] <= y) section++
      return section
    }
    const current = keys.Window.activeFocusItem
    if (!current || !itemInside(current)) { items[forward ? 0 : items.length - 1].forceActiveFocus(); return }
    const sectionCount = headers.length + 1
    const from = sectionOf(itemY(current))
    for (let step = 1; step <= sectionCount; step++) {
      const target = (from + (forward ? step : sectionCount - step)) % sectionCount
      for (let i = 0; i < items.length; i++) {
        if (sectionOf(itemY(items[i])) !== target) continue
        items[i].forceActiveFocus()
        return
      }
    }
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
    onTextKey: function(text) { if (text === "q" && root.bar) root.bar.closePanel(root.moduleName) }
    onTabRequested: function(direction) { root.sectionJump(direction > 0) }
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
