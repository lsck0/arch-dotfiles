import QtQuick
import QtQuick.Effects
import qs.Commons

// Thin-stroke radial arc gauge: a faint track, an accent/criticality value arc,
// optional tick marks, and a centred mono label. Built for the System reactor
// dashboard as a containment ring or an orbital satellite gauge.
// Repaints only when its value / geometry / colour changes (i.e. the data tick),
// never on a clock; glow is gated on Style.fx.glow and paint gated on `active`.
Item {
  id: root

  // 0..1 fraction to sweep.
  property real value: 0
  property color color: Color.accent
  property color trackColor: Util.alpha(Color.foreground, 0.12)
  property real thickness: Style.space(4)
  // Arc opening: 135deg start, 270deg sweep leaves a gap at the bottom.
  property real startAngle: 135
  property real sweepAngle: 270
  property int ticks: 0
  // Centred readout + small caption under it (drawn as crisp Text, not on the Canvas).
  property string text: ""
  property string subText: ""
  property real textSize: Style.font.title
  // Only paints while the panel that owns it is open.
  property bool active: true

  implicitWidth: Style.space(56)
  implicitHeight: Style.space(56)

  onValueChanged: if (active) cv.requestPaint()
  onColorChanged: if (active) cv.requestPaint()
  onTrackColorChanged: if (active) cv.requestPaint()
  onThicknessChanged: if (active) cv.requestPaint()
  onActiveChanged: if (active) cv.requestPaint()
  onWidthChanged: cv.requestPaint()
  onHeightChanged: cv.requestPaint()

  Canvas {
    id: cv
    anchors.fill: parent
    // Canvas drops requestPaint before it is available; paint once it is ready.
    onAvailableChanged: if (available) requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width, h = height
      var cx = w / 2, cy = h / 2
      var r = Math.min(w, h) / 2 - root.thickness / 2 - 1
      if (r <= 0) return
      var a0 = root.startAngle * Math.PI / 180
      var a1 = (root.startAngle + root.sweepAngle) * Math.PI / 180
      var v = Math.max(0, Math.min(1, root.value))

      ctx.lineCap = "round"
      // Track arc.
      ctx.lineWidth = root.thickness
      ctx.strokeStyle = root.trackColor
      ctx.beginPath(); ctx.arc(cx, cy, r, a0, a1); ctx.stroke()
      // Value arc.
      if (v > 0) {
        ctx.strokeStyle = root.color
        ctx.beginPath(); ctx.arc(cx, cy, r, a0, a0 + (a1 - a0) * v); ctx.stroke()
      }
      // Tick marks just inside the arc.
      if (root.ticks > 1) {
        ctx.lineWidth = 1
        ctx.strokeStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 0.35)
        var ri = r - root.thickness / 2 - Style.space(2)
        var ro = r - root.thickness / 2 - 1
        for (var i = 0; i < root.ticks; i++) {
          var a = a0 + (a1 - a0) * (i / (root.ticks - 1))
          ctx.beginPath()
          ctx.moveTo(cx + Math.cos(a) * ri, cy + Math.sin(a) * ri)
          ctx.lineTo(cx + Math.cos(a) * ro, cy + Math.sin(a) * ro)
          ctx.stroke()
        }
      }
    }

    layer.enabled: Style.fx.glow > 0
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: root.color
      shadowBlur: 0.7
      shadowVerticalOffset: 0
      shadowHorizontalOffset: 0
      blurMax: Style.fx.glowRadius
      autoPaddingEnabled: true
    }
  }

  // Centred readout, crisp Text overlay.
  Column {
    anchors.centerIn: parent
    spacing: 0
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.text !== ""
      text: root.text
      color: root.color
      font.family: Style.font.family
      font.pixelSize: root.textSize
      font.bold: true
      font.letterSpacing: Style.displayTracking
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.subText !== ""
      text: root.subText
      color: Color.foreground
      opacity: Style.emphasis.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.capitalization: Font.AllUppercase
      font.letterSpacing: Style.headerTracking * 0.4
    }
  }
}
