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
  default property alias body: inner.flickableData

  property BarWidget anchorWidget: null
  readonly property bool anchored: anchorWidget !== null

  readonly property real edgeMargin: Style.spacing.sm
  readonly property real fadeHeight: Style.space(32)

  // everything around the body: padding, the title and the card's bottom stroke, which the body must not run under
  readonly property real chromeHeight: padding * 2 + titleInset + card.strokeWidth
  readonly property real screenBodyHeight: Math.max(Style.space(120),
    (screen ? screen.height : Style.space(1080)) - Style.bar.sizeHorizontal - Style.gapsOut * 2 - chromeHeight) // qmllint disable missing-property
  // a panel caps its body below the screen's room here; past it the body scrolls
  property real maxBodyHeight: screenBodyHeight
  readonly property real maxHeight: Math.min(maxBodyHeight, screenBodyHeight) + chromeHeight

  // the tallest body child's implicit height: a child filling or anchored to the bottom of the body would otherwise
  // size the body after itself
  readonly property real bodyHeight: {
    var height = 0
    for (const child of inner.contentItem.children) if (child.visible) height = Math.max(height, child.implicitHeight)
    return height
  }
  implicitHeight: Math.min(maxHeight, bodyHeight + chromeHeight)

  readonly property real anchoredLeft: {
    if (!anchored || !bar) return 0
    var centre = anchorWidget.barX + anchorWidget.width / 2
    var maxLeft = Math.max(edgeMargin, bar.width - implicitWidth - edgeMargin)
    return Math.max(edgeMargin, Math.min(maxLeft, centre - implicitWidth / 2))
  }
  // where the panel sits on its screen: the toasts and the desktop widgets give way to it
  readonly property rect screenRect: Qt.rect(anchored ? anchoredLeft : (bar ? bar.width : 0) - Style.spacing.sm - implicitWidth,
    bar ? bar.exclusiveZone : 0, implicitWidth, implicitHeight)

  signal opened()

  readonly property bool shown: bar !== null && bar.activePanel === moduleName
  readonly property bool keyboardOpened: shown && bar.keyboardPanel
  readonly property bool barPinned: shown && bar.pinnedPanel === moduleName

  // a hidden or dropped widget takes its panel off the bar: open, toggle and list refuse it, and an open one closes
  readonly property bool panelRegistered: bar !== null && moduleName !== "" && (!anchored || (anchorWidget.visible && !anchorWidget.dropped))
  onPanelRegisteredChanged: {
    if (panelRegistered) bar.panelRegister(moduleName)
    else if (bar) { bar.closePanel(moduleName); bar.panelUnregister(moduleName) }
  }
  Component.onCompleted: if (panelRegistered) bar.panelRegister(moduleName)
  Component.onDestruction: if (panelRegistered) bar.panelUnregister(moduleName)

  readonly property alias boot: bootIn

  visible: shown || bootIn.progress > 0
  onVisibleChanged: if (!visible && bar && bar.activePanelWindow === root) bar.activePanelWindow = null
  onShownChanged: {
    root.clicked = false
    if (!shown) return
    bar.activePanelWindow = root
    inner.contentY = 0
    if (anchorWidget && anchorWidget.refreshBarX) anchorWidget.refreshBarX()
    keys.forceActiveFocus()
    opened()
  }

  readonly property bool windowActive: keys.Window.active
  onWindowActiveChanged: if (windowActive && keyboardOpened && keys.focus) walkFocus(true, false)
  onKeyboardOpenedChanged: if (windowActive && keyboardOpened && keys.focus) walkFocus(true, false)

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

  // reveal scrolls the body until the item clears the edge fades; the first focus on open leaves the body at its top
  function focusItem(item, reveal) {
    item.forceActiveFocus()
    if (reveal === false || !itemInside(item) || !inner.interactive) return
    var top = item.mapToItem(inner.contentItem, 0, 0).y
    if (top - fadeHeight < inner.contentY) scrollBy(top - fadeHeight - inner.contentY)
    else if (top + item.height + fadeHeight > inner.contentY + inner.height)
      scrollBy(top + item.height + fadeHeight - inner.contentY - inner.height)
  }

  function walkFocus(forward, reveal) {
    var from = keys.Window.activeFocusItem || keys
    var next = from.nextItemInFocusChain(forward)
    if (next && next !== from) focusItem(next, reveal)
  }

  readonly property real scrollStep: Style.space(48)

  function scrollBy(dy) {
    inner.contentY = Math.max(0, Math.min(inner.contentHeight - inner.height, inner.contentY + dy))
  }

  function itemHidden(item, forward) {
    var top = item.mapToItem(inner.contentItem, 0, 0).y
    return forward ? top + item.height > inner.contentY + inner.height : top < inner.contentY
  }

  // j/k walk the focus chain while the next control is in view; past the view's edge, on a wrap or with nothing to
  // focus they scroll the body a step, so rows between and after the controls stay readable
  function moveVertical(forward) {
    var from = keys.Window.activeFocusItem || keys
    var next = from.nextItemInFocusChain(forward)
    var wraps = !next || next === from || !itemInside(next)
      || (itemInside(from) && (forward ? itemY(next) < itemY(from) : itemY(next) > itemY(from)))
    if ((wraps || itemHidden(next, forward)) && inner.interactive && !(forward ? inner.atYEnd : inner.atYBeginning))
      scrollBy((forward ? 1 : -1) * scrollStep)
    else walkFocus(forward)
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
    if (!current || !itemInside(current)) { focusItem(items[forward ? 0 : items.length - 1]); return }
    const sectionCount = headers.length + 1
    const from = sectionOf(itemY(current))
    for (let step = 1; step <= sectionCount; step++) {
      const target = (from + (forward ? step : sectionCount - step)) % sectionCount
      for (let i = 0; i < items.length; i++) {
        if (sectionOf(itemY(items[i])) !== target) continue
        focusItem(items[i])
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
    onMoveRequested: function(dx, dy) {
      if (dy !== 0) root.moveVertical(dy > 0)
      else root.walkFocus(dx > 0)
    }
    onPageRequested: function(direction) { root.scrollBy(direction * (inner.height - root.scrollStep)) }

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

      Flickable {
        id: inner
        x: card.contentLeftInset
        y: card.y + card.contentTopInset + root.titleInset
        width: card.width - card.contentLeftInset - card.contentRightInset
        height: card.height - card.contentTopInset - card.contentBottomInset - root.titleInset
        opacity: bootIn.rowOpacity(1)
        contentWidth: width
        contentHeight: Math.max(height, root.bodyHeight)
        interactive: root.bodyHeight > height
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: interactive
        layer.enabled: interactive
        layer.effect: FadeMask { maskSource: bodyFade }
      }

      // more above or below: the body fades out at that edge and the scroll track shows where the view sits
      Item {
        id: bodyFade
        readonly property real ramp: root.fadeHeight / Math.max(1, height)
        x: inner.x
        y: inner.y
        width: inner.width
        height: inner.height
        visible: false
        layer.enabled: inner.interactive

        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0; color: Util.alpha("black", inner.atYBeginning ? 1 : 0) }
            GradientStop { position: Math.min(0.5, bodyFade.ramp); color: "black" }
            GradientStop { position: Math.max(0.5, 1 - bodyFade.ramp); color: "black" }
            GradientStop { position: 1; color: Util.alpha("black", inner.atYEnd ? 1 : 0) }
          }
        }
      }

      Rectangle {
        id: scrollTrack
        visible: inner.interactive
        x: inner.x + inner.width + (root.padding - width) / 2
        y: inner.y
        width: Math.max(1, Style.space(3))
        height: inner.height
        radius: width / 2
        color: Util.alpha(Colors.accent, Style.emphasis.disabled)
        opacity: inner.opacity

        Rectangle {
          y: inner.visibleArea.yPosition * scrollTrack.height
          width: parent.width
          height: Math.max(parent.width * 4, inner.visibleArea.heightRatio * scrollTrack.height)
          radius: parent.radius
          color: Colors.accent
        }
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
