pragma ComponentBehavior: Bound
import QtQuick

// the one glass every shell card is drawn as: the shell fill over the wallpaper blur, the hairline edge, the chamfer,
// the corner brackets and the scanlines. Children lie between the fill and the brackets
Item {
  id: root

  default property alias content: holder.data
  readonly property alias shape: shape
  property alias docked: shape.docked
  property alias strokeColor: shape.strokeColor
  property real bracketInset: 0
  property bool scanlines: true
  property bool flicker: false

  DockShape {
    id: shape
    anchors.fill: parent
  }

  Item {
    id: holder
    anchors.fill: parent
  }

  Item {
    x: shape.sideInset
    width: parent.width - shape.sideInset * 2
    height: parent.height
    // brackets mark free corners: a docked card's top ones run into the bar
    HudFrame { inset: root.bracketInset; chamfer: shape.cut; chamferCorner: shape.cutCorner; topArms: !shape.docked }
    Scanlines { shown: root.scanlines; flicker: root.flicker }
  }
}
