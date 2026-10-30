import QtQuick
import qs.Commons

// wraps onto further lines once a width is set; without one it stays a single row
Flow {
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
        color: Colors.accentText
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        text: parent.modelData[1]
        color: Colors.textDim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }
}
