import QtQuick
import qs.Commons

// Text with the shell's defaults: plain text in the theme font at body size in the foreground colour. caption takes
// the caption size, icon the icon font, dim the dim text colour; any of them can still be set directly. highlighted is
// for a label on a selected or hovered row: dim text is under 4.5:1 on those fills, so it reads as normal text there.
Text {
  property bool caption: false
  property bool icon: false
  property bool dim: false
  property bool highlighted: false

  textFormat: Text.PlainText
  color: dim && !highlighted ? Colors.textDim : Colors.foreground
  font.family: icon ? Style.font.iconFamily : Style.font.family
  font.pixelSize: caption ? Style.font.caption : Style.font.body
}
