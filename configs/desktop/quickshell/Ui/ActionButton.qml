import QtQuick
import qs.Commons

/**
 * ActionButton: the one text action, `[ LABEL ]` with an optional glyph, square, tinted fill.
 *
 * Properties:
 *   label    drawn uppercase inside brackets
 *   glyph    nerd font glyph before the label, "" hides it
 *   tint     text and fill hue
 *   danger   stronger fill, for destructive actions
 *   focusable  takes tab focus, Enter/Space activate
 *
 * Usage:
 *   ActionButton { label: "run again"; enabled: !root.running; onActivated: root.runAgainRequested() }
 */
Rectangle {
  id: root

  property string label: ""
  property string glyph: ""
  property color tint: Color.menu.text
  property bool danger: false
  property bool focusable: false
  property bool hasCursor: false

  signal activated()

  // fill alphas: rest, hot, plus the danger step
  readonly property real restAlpha: 0.10
  readonly property real hotAlpha: 0.20
  readonly property real dangerStep: 0.08
  readonly property bool hot: (mouse.containsMouse || hasCursor || activeFocus) && enabled

  activeFocusOnTab: focusable
  Keys.onReturnPressed: root.activated()
  Keys.onEnterPressed: root.activated()
  Keys.onSpacePressed: root.activated()

  implicitWidth: row.implicitWidth + Style.spacing.md * 2
  implicitHeight: Style.row.control
  radius: Style.shape.data
  opacity: enabled ? 1 : Style.emphasis.disabled
  color: Util.alpha(tint, (hot ? hotAlpha : restAlpha) + (danger ? dangerStep : 0))
  border.width: activeFocus ? Style.focusBorderWidth : 0
  border.color: Util.alpha(tint, Style.focusBorderAlpha)
  Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.spacing.xs

    Text {
      visible: root.glyph !== ""
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.glyph
      color: root.tint
      font.family: Style.font.iconFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "[ " + root.label + " ]"
      color: root.tint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.capitalization: Font.AllUppercase
      layer.enabled: root.hot && Style.fx.glow > 0
      layer.effect: Glow { shadowColor: root.tint }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.focusable) root.forceActiveFocus()
      root.activated()
    }
  }
}
