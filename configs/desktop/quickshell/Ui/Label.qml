import QtQuick
import qs.Commons

// Text with the shell's defaults: plain text in the theme font at body size in the foreground colour. caption takes
// the caption size, icon the icon font, dim the dim text colour; any of them can still be set directly.
Text {
  property bool caption: false
  property bool icon: false
  property bool dim: false

  textFormat: Text.PlainText
  color: dim ? Colors.textDim : Colors.foreground
  font.family: icon ? Style.font.iconFamily : Style.font.family
  font.pixelSize: caption ? Style.font.caption : Style.font.body
}
