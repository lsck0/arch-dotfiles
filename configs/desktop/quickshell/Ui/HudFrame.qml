pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root
  anchors.fill: parent
  anchors.margins: margin + inset
  visible: shown && Style.fx.brackets
  z: 5

  property bool shown: true
  property color color: Colors.accent
  property int len: Style.fx.bracketLen
  property int thick: Style.fx.bracketWidth
  property real strength: 0.9
  property real margin: 0
  property real inset: 0
  property real chamfer: 0
  property int chamferCorner: Qt.TopRightCorner

  readonly property int hlen: Math.max(0, Math.min(len, Math.floor(width / 2) - thick))
  readonly property int vlen: Math.max(0, Math.min(len, Math.floor(height / 2) - thick))

  readonly property real _c: Math.max(0, Math.min(chamfer - (margin + inset) * (2 - Math.SQRT2),
                                                  width / 2, height / 2))
  readonly property bool _cutTop: _c > 0 && chamferCorner === Qt.TopRightCorner
  readonly property bool _cutBottom: _c > 0 && chamferCorner === Qt.BottomRightCorner

  readonly property real _ch: thick / 2
  readonly property real _cr: width - _ch
  readonly property real _k: _c - thick * (1 - Math.SQRT1_2)

  component Arm: Rectangle {
    color: root.color
    opacity: root.strength
    antialiasing: false
  }

  Arm { x: 0; y: 0; width: root.hlen; height: root.thick }
  Arm { x: 0; y: 0; width: root.thick; height: root.vlen }
  Arm { visible: !root._cutTop; anchors.right: parent.right; y: 0; width: root.hlen; height: root.thick }
  Arm { visible: !root._cutTop; anchors.right: parent.right; y: 0; width: root.thick; height: root.vlen }
  Arm { x: 0; anchors.bottom: parent.bottom; width: root.hlen; height: root.thick }
  Arm { x: 0; anchors.bottom: parent.bottom; width: root.thick; height: root.vlen }
  Arm { visible: !root._cutBottom; anchors.right: parent.right; anchors.bottom: parent.bottom; width: root.hlen; height: root.thick }
  Arm { visible: !root._cutBottom; anchors.right: parent.right; anchors.bottom: parent.bottom; width: root.thick; height: root.vlen }

  Shape {
    visible: root._cutTop || root._cutBottom
    anchors.fill: parent
    opacity: root.strength
    preferredRendererType: Shape.CurveRenderer
    transform: Scale { origin.y: root.height / 2; yScale: root._cutBottom ? -1 : 1 }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.thick
      joinStyle: ShapePath.MiterJoin
      capStyle: ShapePath.FlatCap
      startX: root._cr - root._k - root.hlen; startY: root._ch
      PathLine { x: root._cr - root._k; y: root._ch }
      PathLine { x: root._cr; y: root._ch + root._k }
      PathLine { x: root._cr; y: root._ch + root._k + root.vlen }
    }
  }
}
