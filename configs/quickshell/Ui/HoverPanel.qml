import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Shared chrome + hover wiring for every dropdown-style bar panel:
// BorderSurface card, a click-eating MouseArea (stops clicks falling
// through to Bar's dismiss catcher), and a HoverHandler that reports into
// `bar.hoverPanelEnter/Exit` — the panel-side counterpart to the
// trigger-side reporting WidgetButton does via its entered()/exited()
// signals. Callers declare their content as plain children, same as they
// would inside a bare Column; it lands inside the inset `inner` item via
// the default-property redirect below.
PanelWindow {
  id: root

  property QtObject bar: null
  property string moduleName: ""
  property real padding: Style.spacing.panelPadding
  default property alias data: inner.data

  // Set this to the BarWidget that triggers the panel and it opens centred
  // beneath that widget. Leave it null and the panel keeps the historical
  // top-right anchor, which is still the right answer for right-section
  // widgets: they all sit next to each other, so a shared landing spot means
  // hover can transit from any of them to any panel.
  //
  // It exists for the *centre* section. The SPEC puts the datetime and media
  // widgets there behind hover panels, and a mid-bar trigger is ~950px from
  // a right-anchored panel — far enough that reaching it needs one
  // uninterrupted sweep inside hoverCloseTimer's grace window.
  property Item anchorWidget: null
  readonly property bool anchored: anchorWidget !== null

  // Keeps the card clear of the screen edges when the trigger sits near one.
  readonly property real edgeMargin: Style.spacing.md

  // Centred under the trigger, then clamped into the bar's width so a panel
  // wider than the space beside its trigger slides inward instead of
  // hanging off-screen. Depends on anchorWidget.barX, which BarWidget
  // republishes on every layout change — that dependency is the whole
  // mechanism, so it must stay a property read and not a mapToItem call.
  readonly property real anchoredLeft: {
    if (!anchored || !bar) return 0
    var centre = anchorWidget.barX + anchorWidget.width / 2
    var maxLeft = Math.max(edgeMargin, bar.width - implicitWidth - edgeMargin)
    return Math.max(edgeMargin, Math.min(maxLeft, centre - implicitWidth / 2))
  }

  visible: bar !== null && bar.activePanel === moduleName
  screen: bar && bar.screen ? bar.screen : null

  // Re-read the trigger's position every time the panel opens. The layout
  // signals below keep barX fresh in the general case, but this is the one
  // moment correctness is actually observable, so it is worth not relying
  // on them alone.
  onVisibleChanged: if (visible && anchorWidget && anchorWidget.refreshBarX) anchorWidget.refreshBarX()
  color: "transparent"

  // Anchoring one horizontal edge and offsetting from it is what positions a
  // layer-shell surface; there is no free-floating x. Anchoring *both* edges
  // would stretch the surface across the screen instead.
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
  // Opt-in, defaulting to None. A hover panel that grabbed the keyboard
  // would pull focus off whatever you were typing in the moment it opened,
  // and most panels have nothing to type into. Panels that DO carry a text
  // field (the Display panel's font search) set this, and OnDemand means
  // they only take focus on an actual click, handing it back when the panel
  // closes on hover-exit.
  property bool acceptsKeyboard: false
  WlrLayershell.keyboardFocus: root.acceptsKeyboard
    ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  // The card is inset from the window by exactly the shadow offset, so the
  // hard shadow has somewhere to land. Filling the window instead clips the
  // shadow away entirely — invisible on a right-anchored panel, which is
  // most of them.
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

  // Do not place a click-eating MouseArea over the card: panel controls
  // (calendar, sliders, buttons, and text fields) must receive pointer input.
  // Each interactive child owns its own MouseArea.

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
