import QtQuick
import qs.Commons

Text {
  id: root

  property color foreground: Colors.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.caption

  textFormat: Text.PlainText
  color: foreground
  font.family: fontFamily
  font.pixelSize: fontSize
  font.bold: true

  font.capitalization: Font.AllUppercase
  font.letterSpacing: Style.headerTracking

  topPadding: Math.ceil(fontSize * 0.15)
  leftPadding: prefix.implicitWidth

  Text {
    id: prefix
    y: root.topPadding
    textFormat: Text.PlainText
    text: "> "
    color: root.color
    font: root.font
  }

  layer.enabled: Style.fx.glow > 0
  layer.effect: Glow {}
}
