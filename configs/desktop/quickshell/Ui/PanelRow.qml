import QtQuick
import qs.Commons

Rectangle {
  id: root

  property string label: ""
  property string glyph: ""
  property string trailing: ""

  property bool stateMarker: false

  property bool on: false

  property bool filled: false
  property bool centered: false

  signal activated()

  activeFocusOnTab: enabled
  Keys.onReturnPressed: root.activated()
  Keys.onEnterPressed: root.activated()
  Keys.onSpacePressed: root.activated()

  height: Style.row.list
  radius: Style.shape.data
  opacity: enabled ? 1 : Style.emphasis.disabled

  readonly property color _text: on ? Colors.menu.selectedText : Colors.menu.text

  color: mouse.pressed && enabled ? Style.pressedFillFor(Colors.foreground, Colors.accent)
    : on ? Colors.menu.selectedBackground
    : activeFocus ? Style.focusFillFor(Colors.foreground, Colors.accent)
    : mouse.containsMouse && enabled ? Style.hoverFill
    : filled ? Style.normalFill
    : "transparent"

  Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }

  Row {
    id: content
    anchors.left: root.centered ? undefined : parent.left
    anchors.leftMargin: root.centered ? 0 : Style.spacing.sm
    anchors.horizontalCenter: root.centered ? parent.horizontalCenter : undefined
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xs

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
      layer.effect: Glow {}
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
      layer.effect: Glow {}
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, Math.min(implicitWidth, root.width - Style.spacing.sm * 2
        - (glyphText.visible ? glyphText.implicitWidth + content.spacing : 0)
        - (markerText.visible ? markerText.implicitWidth + content.spacing : 0)
        - (trailingText.visible ? trailingText.implicitWidth + Style.spacing.xs : 0)))
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
    anchors.rightMargin: Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.trailing
    color: Colors.menu.text
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

  Text {
    visible: root.activeFocus || (mouse.containsMouse && root.enabled)
    opacity: root.activeFocus ? 1 : Style.emphasis.faint
    anchors.right: parent.left
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: ">"
    color: Colors.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
