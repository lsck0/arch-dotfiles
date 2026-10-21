import QtQuick
import qs.Commons

Row {
  id: root

  property var hints: []

  spacing: Style.spacing.md

  Repeater {
    model: root.hints

    Row {
      required property var modelData
      spacing: Style.spacing.xs

      Text {
        textFormat: Text.PlainText
        text: "[" + parent.modelData[0] + "]"
        color: Colors.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        text: parent.modelData[1]
        color: Colors.foreground
        opacity: Style.emphasis.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }
}
