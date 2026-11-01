import QtQuick
import qs.Commons

Rectangle {
  id: root

  property string label: ""
  property string glyph: ""
  property string trailing: ""

  property bool stateMarker: false
  // labels read like the stat rows beside them; a name (a player, a module) opts out
  property bool upper: true

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

  Rectangle {
    visible: root.on
    width: Style.selectedBorderWidth
    height: parent.height
    color: Style.selectedMarkColor(Colors.menu.text, Colors.accent)
  }

  Row {
    id: content
    anchors.left: root.centered ? undefined : parent.left
    anchors.leftMargin: root.centered ? 0 : Style.spacing.sm
    anchors.horizontalCenter: root.centered ? parent.horizontalCenter : undefined
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xs

    Label {
      id: glyphText
      anchors.verticalCenter: parent.verticalCenter
      visible: root.glyph !== ""
      text: root.glyph
      color: root._text
      icon: true
      font.pixelSize: Style.font.icon

      layer.enabled: Style.fx.glow > 0 && root.on
      layer.effect: Glow {}
    }

    Label {
      id: markerText
      anchors.verticalCenter: parent.verticalCenter
      visible: root.glyph === "" && root.stateMarker
      text: root.on ? "*" : "o"
      color: root._text

      layer.enabled: Style.fx.glow > 0 && root.on
      layer.effect: Glow {}
    }

    Label {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, Math.min(implicitWidth, root.width - Style.spacing.sm * 2
        - (glyphText.visible ? glyphText.implicitWidth + content.spacing : 0)
        - (markerText.visible ? markerText.implicitWidth + content.spacing : 0)
        - (trailingText.visible ? trailingText.implicitWidth + Style.spacing.xs : 0)))
      text: root.label
      color: root._text
      font.capitalization: root.upper ? Font.AllUppercase : Font.MixedCase
      font.letterSpacing: root.upper ? Style.labelTracking : 0
      elide: Text.ElideRight
    }
  }

  Label {
    id: trailingText
    visible: root.trailing !== ""
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    text: root.trailing
    color: root.on ? Colors.menu.text : Colors.textDim
    caption: true
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  Label {
    visible: root.activeFocus || (mouse.containsMouse && root.enabled)
    opacity: root.activeFocus ? 1 : Style.emphasis.faint
    anchors.right: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: ">"
    color: Colors.accentText
    caption: true
  }
}
