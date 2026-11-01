import QtQuick
import qs.Commons

// One reading in a panel: a caption with its value, either below it as a tile or beside it on one line, an optional
// note, and optionally a sparkline of its history and a fraction gauge, all in one tint. clickable makes the whole
// row a focusable link that emits activated.
Item {
  id: root

  property string glyph: ""
  property real glyphRotation: 0
  property string label: ""
  property string value: ""
  property string note: ""
  property color tint: Colors.menu.text
  property bool valueBeside: false
  property real valueSize: Style.font.body
  property var history: []
  property real historyMax: 100
  // a gauge is drawn only for a fraction of 0 or more
  property real fraction: -1
  property bool clickable: false

  signal activated()

  readonly property color textColor: Colors.textFor(tint)

  width: parent ? parent.width : 0
  implicitHeight: body.implicitHeight
  activeFocusOnTab: clickable
  Keys.onReturnPressed: root.activated()
  Keys.onEnterPressed: root.activated()
  Keys.onSpacePressed: root.activated()

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: -Style.spacing.xs
    anchors.rightMargin: -Style.spacing.xs
    visible: root.clickable
    radius: Style.shape.data
    color: root.activeFocus ? Style.focusFillFor(Colors.foreground, Colors.accent) : mouse.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
  }

  Column {
    id: body
    width: root.width
    spacing: Style.spacing.xxs

    Item {
      width: root.width
      implicitHeight: Math.max(captionRow.implicitHeight, beside.implicitHeight)

      Row {
        id: captionRow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs

        Label {
          id: glyphLabel
          visible: root.glyph !== ""
          text: root.glyph
          rotation: root.glyphRotation
          dim: true
          icon: true
          caption: true
        }

        // a Row neither resizes nor clips its children, so the caption itself is capped to elide before the value
        Label {
          width: Math.max(0, Math.min(implicitWidth, root.width - (root.valueBeside ? beside.implicitWidth + Style.spacing.sm : 0) - (glyphLabel.visible ? glyphLabel.width + captionRow.spacing : 0)))
          text: root.label
          elide: Text.ElideRight
          color: root.valueBeside ? root.textColor : Colors.menu.text
          caption: true
          font.bold: root.valueBeside
          font.capitalization: Font.AllUppercase
          font.letterSpacing: root.valueBeside ? Style.headerTracking : Style.labelTracking
        }
      }

      Row {
        id: beside
        visible: root.valueBeside
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.sm

        Label {
          text: root.value
          color: root.textColor
          caption: true
          font.letterSpacing: Style.displayTracking
          font.features: { "tnum": 1 }
        }

        Label {
          visible: root.note !== ""
          text: root.note
          dim: true
          caption: true
          font.features: { "tnum": 1 }
        }
      }
    }

    Label {
      visible: !root.valueBeside
      width: root.width
      text: root.value
      elide: Text.ElideRight
      color: root.textColor
      font.pixelSize: root.valueSize
      font.letterSpacing: Style.displayTracking
      font.features: { "tnum": 1 }
    }

    Label {
      visible: !root.valueBeside && root.note !== ""
      width: root.width
      text: root.note
      elide: Text.ElideRight
      dim: true
      caption: true
    }

    Sparkline {
      width: root.width
      height: Style.space(34)
      values: root.history
      minValue: 0
      maxValue: root.historyMax
      color: root.tint
    }

    BarGauge {
      visible: root.fraction >= 0
      width: root.width
      height: Style.spacing.sm
      segments: 24
      value: root.fraction
      color: root.tint
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.clickable
    hoverEnabled: root.clickable
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
