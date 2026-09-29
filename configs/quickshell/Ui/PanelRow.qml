import QtQuick
import QtQuick.Effects
import qs.Commons

Rectangle {
  id: root

  property string label: ""
  property string glyph: ""
  property string trailing: ""

  // show on/off as a dot instead of an icon
  property bool stateMarker: false

  property bool on: false

  // button-style row resting on a fill
  property bool filled: false
  property bool centered: false

  property bool enabled: true

  signal activated()

  height: Style.row.list
  radius: Style.cornerRadius
  opacity: enabled ? 1 : Style.emphasis.disabled

  readonly property color _text: on ? Color.menu.selectedText : Color.menu.text

  color: on ? Color.menu.selectedBackground
    : mouse.containsMouse && enabled ? Style.hoverFill
    : filled ? Style.normalFill
    : "transparent"

  Behavior on color { ColorAnimation { duration: 100 } }

  Row {
    id: content
    anchors.left: root.centered ? undefined : parent.left
    anchors.leftMargin: root.centered ? 0 : Style.spacing.md
    anchors.horizontalCenter: root.centered ? parent.horizontalCenter : undefined
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.sm

    Text {
      id: glyphText
      anchors.verticalCenter: parent.verticalCenter
      visible: root.glyph !== ""
      textFormat: Text.PlainText
      text: root.glyph
      color: root._text
      font.family: Style.font.iconFamily
      font.pixelSize: Style.font.icon

      layer.enabled: Style.fx.glow > 0 && root.on
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Style.fx.glowColor
        shadowBlur: 1.0
        shadowVerticalOffset: 0
        shadowHorizontalOffset: 0
        blurMax: Style.fx.glowRadius
        autoPaddingEnabled: true
      }
    }

    Text {
      id: markerText
      anchors.verticalCenter: parent.verticalCenter
      visible: root.glyph === "" && root.stateMarker
      textFormat: Text.PlainText
      text: root.on ? "*" : "o"
      color: root._text
      font.family: Style.font.family
      font.pixelSize: Style.font.body

      layer.enabled: Style.fx.glow > 0 && root.on
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Style.fx.glowColor
        shadowBlur: 1.0
        shadowVerticalOffset: 0
        shadowHorizontalOffset: 0
        blurMax: Style.fx.glowRadius
        autoPaddingEnabled: true
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, Math.min(implicitWidth, root.width - Style.spacing.md * 2
        - (glyphText.visible ? glyphText.implicitWidth + content.spacing : 0)
        - (markerText.visible ? markerText.implicitWidth + content.spacing : 0)
        - (trailingText.visible ? trailingText.implicitWidth + Style.spacing.sm : 0)))
      textFormat: Text.PlainText
      text: root.label
      color: root._text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }

  Text {
    id: trailingText
    visible: root.trailing !== ""
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.md
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.trailing
    color: Color.menu.text
    opacity: root.on ? 1 : Style.emphasis.faint
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
