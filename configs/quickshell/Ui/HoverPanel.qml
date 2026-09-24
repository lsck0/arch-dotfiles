import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Shared chrome + hover wiring for every dropdown-style bar panel: BorderSurface card, a click-eating MouseArea (stops clicks falling through to Bar's dismiss catcher), and a HoverHandler that reports into `bar.hoverPanelEnter/Exit` — the panel-side counterpart to the trigger-side reporting WidgetButton does via its entered()/exited() signals. Callers declare their content as plain children, same as they would inside a bare Column; it lands inside the inset `inner` item via the default-property redirect below.
PanelWindow {
  id: root

  property QtObject bar: null
  property string moduleName: ""
  property real padding: Style.spacing.panelPadding
  default property alias data: inner.data

  // Set this to the BarWidget that triggers the panel and it opens centred beneath that widget.
  property Item anchorWidget: null
  readonly property bool anchored: anchorWidget !== null

  // Keeps the card clear of the screen edges when the trigger sits near one.
  readonly property real edgeMargin: Style.spacing.md

  // Centred under the trigger, then clamped into the bar's width so a panel wider than the space beside its trigger slides inward instead of hanging off-screen.
  readonly property real anchoredLeft: {
    if (!anchored || !bar) return 0
    var centre = anchorWidget.barX + anchorWidget.width / 2
    var maxLeft = Math.max(edgeMargin, bar.width - implicitWidth - edgeMargin)
    return Math.max(edgeMargin, Math.min(maxLeft, centre - implicitWidth / 2))
  }

  // Emitted every time the panel comes up, however it was opened.
  signal opened()

  visible: bar !== null && bar.activePanel === moduleName
  // One handler: QML allows a signal only one handler per object, and a second `onVisibleChanged` here is a load-time error, not an addition.
  onVisibleChanged: {
    if (!visible) return
    if (anchorWidget && anchorWidget.refreshBarX) anchorWidget.refreshBarX()
    opened()
  }

  screen: bar && bar.screen ? bar.screen : null
  color: "transparent"

  // Anchoring one horizontal edge and offsetting from it is what positions a layer-shell surface; there is no free-floating x.
  anchors {
    top: true
    left: root.anchored
    right: !root.anchored
  }
  margins {
    // NOT barSize + 4. The bar sets exclusiveZone = barSize, so a top-anchored
    // layer surface already starts below the bar; adding barSize again put
    // every panel 30px lower than intended and opened a 34px dead gap between
    // trigger and panel that hover had to cross. Verified: top=4 lands the
    // panel at y=34 with a 30px bar.
    top: Style.spacing.sm
    left: root.anchored ? root.anchoredLeft : 0
    right: root.anchored ? 0 : Style.spacing.lg
  }

  WlrLayershell.namespace: "quickshell-" + (moduleName || "panel")
  WlrLayershell.layer: WlrLayer.Overlay
  // Opt-in, defaulting to None.
  property bool acceptsKeyboard: false
  WlrLayershell.keyboardFocus: root.acceptsKeyboard
    ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  // The card is inset from the window by exactly the shadow offset, so the hard shadow has somewhere to land.
  BorderSurface {
    id: card
    x: 0
    y: 0
    width: parent.width - Style.shadowOffset
    height: parent.height - Style.shadowOffset
    color: Color.menu.background
    borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
    radius: Style.cornerRadius
    padding: root.padding
  }

  // Do not place a click-eating MouseArea over the card: panel controls (calendar, sliders, buttons, and text fields) must receive pointer input.

  HoverHandler {
    onHoveredChanged: {
      if (!root.bar) return
      if (hovered) root.bar.hoverPanelEnter(root.moduleName)
      else root.bar.hoverPanelExit(root.moduleName)
    }
  }

  Item {
    id: inner
    x: card.contentLeftInset
    y: card.contentTopInset
    width: card.width - card.contentLeftInset - card.contentRightInset
    height: card.height - card.contentTopInset - card.contentBottomInset
  }
}
