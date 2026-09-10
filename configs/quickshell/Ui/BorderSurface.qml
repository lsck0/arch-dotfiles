import QtQuick
import qs.Commons

// Rectangle-compatible surface with Omarchy border specs. Uses native
// Rectangle.border for cheap flat/uniform borders and BorderOverlay for
// gradients or per-side widths.
Rectangle {
  id: root

  property var borderSpec: Border.none()
  property real padding: 0
  property real topPadding: padding
  property real rightPadding: padding
  property real bottomPadding: padding
  property real leftPadding: padding

  readonly property real borderTop: Border.top(borderSpec)
  readonly property real borderRight: Border.right(borderSpec)
  readonly property real borderBottom: Border.bottom(borderSpec)
  readonly property real borderLeft: Border.left(borderSpec)
  readonly property real contentTopInset: borderTop + topPadding
  readonly property real contentRightInset: borderRight + rightPadding
  readonly property real contentBottomInset: borderBottom + bottomPadding
  readonly property real contentLeftInset: borderLeft + leftPadding
  readonly property bool usesOverlayBorder: Border.needsOverlay(borderSpec)

  // Offset shadow, drawn BEHIND this surface (z: -1) rather than as a blur
  // or glow. Opt-out via `shadow: false` for surfaces that are already
  // flush against something — a shadow only reads as depth when there is
  // background to cast onto.
  property bool shadow: true
  property int shadowOffset: Style.shadowOffset

  Rectangle {
    z: -1
    x: root.shadowOffset
    y: root.shadowOffset
    width: root.width
    height: root.height
    radius: root.radius
    visible: root.shadow && root.shadowOffset > 0
    // A palette role, not a flat black: over a warm wallpaper a pure-black
    // slab reads as a hole punched in the desktop rather than as depth.
    color: Util.alpha(Color.shadow, Style.shadowAlpha)
    // The radius is small but non-zero, so an unantialiased edge would show
    // as a jagged corner behind a crisp one.
    antialiasing: true
  }

  border.color: Border.canUseNative(borderSpec) ? Border.color(borderSpec) : "transparent"
  border.width: Border.canUseNative(borderSpec) ? Border.uniformWidth(borderSpec) : 0

  Loader {
    anchors.fill: parent
    active: root.usesOverlayBorder

    sourceComponent: BorderOverlay {
      anchors.fill: parent
      radius: root.radius
      borderSpec: root.borderSpec
    }
  }
}
