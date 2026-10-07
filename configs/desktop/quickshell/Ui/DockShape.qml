import QtQuick
import QtQuick.Shapes
import qs.Commons

/**
 * DockShape: the outline and fill of every floating surface, one Shape.
 *
 * Docked, the edge toward the bar stays open and flares into the bar's accent rule through two
 * inverted corners (the neck), so the drawer reads as bent out of that rule; the far outer corner is
 * chamfered. Free, it is a closed card with the chamfer on the top-right corner. The geometry is
 * static and cached in a layer: animate a clipping parent, never this item's size.
 *
 * Properties:
 *   docked       open top edge with neck (bar above)
 *   flipped      mirror vertically, for a bar below
 *   fillColor    surface fill, translucent over layer blur
 *   strokeColor  outline, the bar rule's accent by default
 *   strokeWidth  outline width
 *
 * Content insets: sideInset (neck) + strokeWidth + padding left and right.
 *
 * Usage:
 *   DockShape { anchors.fill: parent; docked: true; fillColor: Color.menu.background }
 */
Item {
  id: root

  property bool docked: false
  property bool flipped: false
  property color fillColor: Color.menu.background
  property color strokeColor: Util.alpha(Color.accent, Style.surface.ruleAlpha)
  // docked it matches the bar rule it continues
  property real strokeWidth: docked ? Math.max(1, Style.fx.bracketWidth) : Style.surface.borderWidth
  property real chamfer: Style.shape.chamfer

  readonly property real neck: docked ? Style.shape.neck : 0
  readonly property real sideInset: neck

  // half-pixel inset keeps the stroke inside the item
  readonly property real _h: strokeWidth / 2
  readonly property real _l: neck + _h
  readonly property real _r: width - neck - _h
  readonly property real _t: _h
  readonly property real _b: height - _h
  readonly property real _c: Math.max(0, Math.min(chamfer, (_r - _l) / 2, (_b - _t) / 2))
  // the neck curves end this far below the bar rule
  readonly property real _n: neck + _h

  layer.enabled: width > 0 && height > 0
  layer.smooth: true

  transform: Scale { origin.y: root.height / 2; yScale: root.flipped ? -1 : 1 }

  Shape {
    anchors.fill: parent
    visible: root.width > 0 && root.height > 0
    preferredRendererType: Shape.CurveRenderer

    // free card: closed outline, chamfer top-right
    ShapePath {
      fillColor: root.docked ? "transparent" : root.fillColor
      strokeColor: root.docked ? "transparent" : root.strokeColor
      strokeWidth: root.docked ? 0 : root.strokeWidth
      joinStyle: ShapePath.MiterJoin
      startX: root._l; startY: root._t
      PathLine { x: root._r - root._c; y: root._t }
      PathLine { x: root._r; y: root._t + root._c }
      PathLine { x: root._r; y: root._b }
      PathLine { x: root._l; y: root._b }
      PathLine { x: root._l; y: root._t }
    }

    // drawer fill: flares to the full width at the bar, chamfer on the far corner
    ShapePath {
      fillColor: root.docked ? root.fillColor : "transparent"
      strokeColor: "transparent"
      strokeWidth: 0
      startX: 0; startY: 0
      PathLine { x: root.width; y: 0 }
      PathQuad { x: root._r; y: root._n; controlX: root._r; controlY: 0 }
      PathLine { x: root._r; y: root._b - root._c }
      PathLine { x: root._r - root._c; y: root._b }
      PathLine { x: root._l; y: root._b }
      PathLine { x: root._l; y: root._n }
      PathQuad { x: 0; y: 0; controlX: root._l; controlY: 0 }
    }

    // drawer outline: open toward the bar, so the bar rule continues into it
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.docked ? root.strokeColor : "transparent"
      strokeWidth: root.docked ? root.strokeWidth : 0
      joinStyle: ShapePath.MiterJoin
      capStyle: ShapePath.FlatCap
      startX: root.width; startY: root._t
      PathQuad { x: root._r; y: root._n; controlX: root._r; controlY: root._t }
      PathLine { x: root._r; y: root._b - root._c }
      PathLine { x: root._r - root._c; y: root._b }
      PathLine { x: root._l; y: root._b }
      PathLine { x: root._l; y: root._n }
      PathQuad { x: 0; y: root._t; controlX: root._l; controlY: root._t }
    }
  }
}
