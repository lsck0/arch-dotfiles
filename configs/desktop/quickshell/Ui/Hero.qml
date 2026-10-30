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

  Text {
    id: number
    anchors.bottom: parent.bottom
    textFormat: Text.PlainText
    text: root.value
    color: Colors.textFor(root.color)
    font.family: Style.font.family
    font.pixelSize: root.size
    font.bold: true
    font.letterSpacing: Style.displayTracking
    font.features: { "tnum": 1 }
    style: root.live && Style.fx.glow > 0 ? Text.Outline : Text.Normal
    styleColor: Util.alpha(root.color, 0.35)
    layer.enabled: !root.live && Style.fx.glow > 0
    layer.effect: Glow { shadowColor: root.color }
  }

  Text {
    visible: root.unit !== ""
    anchors.baseline: number.baseline
    textFormat: Text.PlainText
    text: root.unit
    // the unit can carry the meaning (rx or tx, kbps or fps): dimmed with the readable textDim, not with opacity
    color: Colors.textDim
    font.family: Style.font.family
    font.pixelSize: Style.font.title
    font.capitalization: Font.AllUppercase
    font.letterSpacing: Style.labelTracking
  }
}
