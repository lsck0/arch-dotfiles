pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

Row {
  id: root

  property string value: "--"
  property string unit: ""
  property color color: Colors.accentText
  property bool live: false
  property int size: Style.font.hero

  spacing: Style.spacing.xs

  Label {
    id: number
    anchors.bottom: parent.bottom
    text: root.value
    color: Colors.textFor(root.color)
    font.pixelSize: root.size
    font.bold: true
    font.letterSpacing: Style.displayTracking
    font.features: { "tnum": 1 }
    style: root.live && Style.fx.glow > 0 ? Text.Outline : Text.Normal
    styleColor: Util.alpha(root.color, 0.35)
    layer.enabled: !root.live && Style.fx.glow > 0
    layer.effect: Glow { shadowColor: root.color }
  }

  Label {
    visible: root.unit !== ""
    anchors.baseline: number.baseline
    text: root.unit
    // the unit can carry the meaning (rx or tx, kbps or fps): dimmed with the readable textDim, not with opacity
    dim: true
    font.pixelSize: Style.font.title
    font.capitalization: Font.AllUppercase
    font.letterSpacing: Style.labelTracking
  }
}
