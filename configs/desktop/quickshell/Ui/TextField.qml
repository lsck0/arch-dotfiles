import QtQuick
import QtQuick.Controls
import qs.Commons

TextField {
  id: root

  property color foreground: Colors.foreground
  property color accent: Colors.accent
  property color selectionTint: Style.selectionFillFor(foreground, accent)
  property bool password: false
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.inputPaddingY

  property bool hasCursor: false

  readonly property bool _focused: activeFocus
  readonly property bool _hot: hovered || hasCursor
  readonly property var _borderSpec: Border.controlSpec(_focused ? "focus" : (_hot ? "hover-cursor" : "normal"), root.foreground, root.accent)

  echoMode: password ? TextInput.Password : TextInput.Normal
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  color: foreground
  selectionColor: selectionTint
  selectedTextColor: foreground
  placeholderTextColor: Util.alpha(foreground, Style.emphasis.faint)

  Keys.onPressed: function (event) {
    if (root.readOnly || !Util.isWordDelete(event.key, event.modifiers)) return
    if (root.selectedText !== "") root.remove(root.selectionStart, root.selectionEnd)
    else root.remove(root.echoMode !== TextInput.Normal ? 0 : Util.wordStart(root.text, root.cursorPosition), root.cursorPosition)
    root.textEdited()
    event.accepted = true
  }

  leftPadding: horizontalPadding + Border.width(_borderSpec)
  rightPadding: horizontalPadding + Border.width(_borderSpec)
  topPadding: verticalPadding + Border.width(_borderSpec)
  bottomPadding: verticalPadding + Border.width(_borderSpec)

  background: BorderSurface {
    color: Style.controlFill(root._focused, root._hot, root.foreground, root.accent)
    borderSpec: root._borderSpec
    radius: Style.shape.data

    layer.enabled: Style.fx.glow > 0 && root._focused
    layer.effect: Glow {}
  }
}
