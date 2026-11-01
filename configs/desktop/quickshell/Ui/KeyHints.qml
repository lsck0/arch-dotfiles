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

      Label {
        text: "[" + parent.modelData[0] + "]"
        color: Colors.accentText
        caption: true
        font.bold: true
      }
      Label {
        text: parent.modelData[1]
        dim: true
        caption: true
      }
    }
  }
}
