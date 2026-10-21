import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root

  property bool docked: false
  property bool flipped: false
  property color fillColor: Colors.menu.background
  property color strokeColor: Util.alpha(Colors.accent, Style.surface.ruleAlpha)
  property real strokeWidth: docked ? Math.max(1, Style.fx.bracketWidth) : Style.surface.borderWidth
  property real chamfer: Style.shape.chamfer

  property bool glow: false
  Component { id: glowEffect; Glow {} }

  property real neck: docked ? Style.shape.neck : 0
  readonly property real sideInset: neck

  readonly property real _h: strokeWidth / 2
  readonly property real _l: neck + _h
  readonly property real _r: width - neck - _h
  readonly property real _t: _h
  readonly property real _b: height - _h
  readonly property real _c: Math.max(0, Math.min(chamfer, (_r - _l) / 2, (_b - _t) / 2))
  readonly property real cut: _c
  readonly property int cutCorner: docked !== flipped ? Qt.BottomRightCorner : Qt.TopRightCorner
  readonly property real _n: neck + _h

  layer.enabled: width > 0 && height > 0
  layer.smooth: true
  layer.effect: root.glow && Style.fx.glow > 0 ? glowEffect : null

  transform: Scale { origin.y: root.height / 2; yScale: root.flipped ? -1 : 1 }

  Shape {
    anchors.fill: parent
    visible: root.width > 0 && root.height > 0
    preferredRendererType: Shape.CurveRenderer

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
