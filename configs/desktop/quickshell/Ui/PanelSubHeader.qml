import QtQuick
import qs.Commons

// a heading inside a section: no prefix, no glow, and no stop for the panel's Tab jump
Label {
  color: Colors.accentText
  caption: true
  font.capitalization: Font.AllUppercase
  font.letterSpacing: Style.headerTracking
}
