import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// dropdown bar panel chrome, reports hover to the bar
PanelWindow {
  id: root

  property QtObject bar: null
  property string moduleName: ""
  property real padding: Style.spacing.panelPadding
  property string title: ""
  // add to implicitHeight
  readonly property real titleInset: titleBar.visible ? titleBar.height + Style.spacing.md : 0
  default property alias data: inner.data

  // opens centred under this bar widget
  property Item anchorWidget: null
  readonly property bool anchored: anchorWidget !== null

  readonly property real edgeMargin: Style.spacing.md

  readonly property real anchoredLeft: {
    if (!anchored || !bar) return 0
    var centre = anchorWidget.barX + anchorWidget.width / 2
    var maxLeft = Math.max(edgeMargin, bar.width - implicitWidth - edgeMargin)
    return Math.max(edgeMargin, Math.min(maxLeft, centre - implicitWidth / 2))
  }

  signal opened()

  // window stays mapped until the fade-out ends
  readonly property bool shown: bar !== null && bar.activePanel === moduleName
  readonly property real slideDistance: Style.space(6)
  readonly property real slideClosedY: (bar && bar.position === "bottom") ? slideDistance : -slideDistance

  visible: shown || body.opacity > 0
  onShownChanged: {
    if (!shown) return
    if (anchorWidget && anchorWidget.refreshBarX) anchorWidget.refreshBarX()
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
    // not barSize: the exclusive zone already starts below the bar
    top: Style.spacing.sm
    left: root.anchored ? root.anchoredLeft : 0
    right: root.anchored ? 0 : Style.spacing.lg
  }

  WlrLayershell.namespace: "quickshell-" + (moduleName || "panel")
  WlrLayershell.layer: WlrLayer.Overlay
  property bool acceptsKeyboard: false
  WlrLayershell.keyboardFocus: root.acceptsKeyboard
    ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  HoverHandler {
    onHoveredChanged: {
      if (!root.bar) return
      if (hovered) root.bar.hoverPanelEnter(root.moduleName)
      else root.bar.hoverPanelExit(root.moduleName)
    }
  }

  Item {
    id: body
    anchors.fill: parent
    opacity: root.shown ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    transform: Translate {
      y: root.shown ? 0 : root.slideClosedY
      Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }

    BorderSurface {
      id: card
      anchors.fill: parent
      color: Color.menu.background
      borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
      radius: Style.cornerRadius
      padding: root.padding

      HudFrame {}
    }

    Item {
      id: inner
      x: card.contentLeftInset
      y: card.contentTopInset + root.titleInset
      width: card.width - card.contentLeftInset - card.contentRightInset
      height: card.height - card.contentTopInset - card.contentBottomInset - root.titleInset
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
      decor: true
      rule: true
      blinking: visible && root.visible
    }
  }
}
