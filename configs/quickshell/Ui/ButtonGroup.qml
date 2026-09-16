import QtQuick
import qs.Commons

// Mutually-exclusive row of Buttons — the form-style "pick one of N"
// pattern (bar position top/right/bottom/left, theme preset chips, etc.).
// Emits `changed(value)` when the user activates a different option.
//
// `options` is either a plain string[] (label == value) or an array of
// { value, label, icon?, tooltip? } objects. Mixing is fine.
//
// Keyboard navigation. The group itself is a single Tab stop, not one
// stop per chip — so in a form that walks `activeFocusOnTab` items with
// Tab / j / k, the cursor enters the group as a unit. Once focused,
// h / l / Left / Right walks between chips and Enter / Space activates
// the current one. The selected chip is the default landing point so
// users see their existing choice on arrival.
//
// Panel-cursor consumers (the bar widget panels) drive `cursorIndex`
// directly and listen on `hovered` to sync the mouse — Tab focus and
// `cursorIndex` are independent; either one paints the chip's hot
// state, and the bar widget panels never give Tab focus to a
// ButtonGroup so they only see the cursorIndex path.
Row {
  id: root

  property var options: []
  property string value: ""
  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property bool focusable: true
  // Stretch chips so the row spans its full width. Needs an explicit width.
  property bool fill: false

  // -1 disables the external cursor highlight (the panel-cursor case).
  // Driven by a containing panel; the group's own Tab-focus h/l
  // tracking is internal and lives in _focusedIndex.
  property int cursorIndex: -1

  // Internal: which chip h / l / Left / Right is currently sitting on
  // when the group itself has Tab focus. Reset to the selected option
  // each time focus arrives so the user sees their existing choice.
  property int _focusedIndex: -1

  signal changed(string value)
  signal hovered(int index, bool isHovered)

  spacing: Style.spacing.md

  // Width left over past the chips' natural sizes, split evenly between them.
  readonly property int _slack: {
    if (!fill || chips.count === 0) return 0
    var natural = spacing * (chips.count - 1)
    for (var i = 0; i < chips.count; i++) {
      var item = chips.itemAt(i)
      if (!item) return 0
      natural += item.implicitWidth
    }
    return Math.max(0, Math.floor(width - natural))
  }

  activeFocusOnTab: focusable

  function optionValue(o) {
    return (o && typeof o === "object") ? String(o.value) : String(o)
  }
  function optionLabel(o) {
    return (o && typeof o === "object" && o.label !== undefined) ? String(o.label) : String(o)
  }
  function optionIcon(o) {
    return (o && typeof o === "object" && o.icon) ? String(o.icon) : ""
  }
  function optionTooltip(o) {
    return (o && typeof o === "object" && o.tooltip) ? String(o.tooltip) : ""
  }

  function selectedOptionIndex() {
    for (var i = 0; i < options.length; i++)
      if (optionValue(options[i]) === value) return i
    return -1
  }

  function activateFocused() {
    if (_focusedIndex < 0 || _focusedIndex >= options.length) return
    var v = optionValue(options[_focusedIndex])
    root.changed(v)
  }

  onActiveFocusChanged: {
    if (activeFocus) {
      var idx = selectedOptionIndex()
      _focusedIndex = idx < 0 ? 0 : idx
    } else {
      _focusedIndex = -1
    }
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Left || event.key === Qt.Key_H
        || event.text === "h") {
      _focusedIndex = Math.max(0, (_focusedIndex < 0 ? 0 : _focusedIndex) - 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L
        || event.text === "l") {
      var max = options.length - 1
      var next = (_focusedIndex < 0 ? 0 : _focusedIndex) + 1
      _focusedIndex = Math.min(max, next)
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        || event.key === Qt.Key_Space) {
      activateFocused()
      event.accepted = true
    }
  }

  Repeater {
    id: chips
    model: root.options

    delegate: Chip {
      required property var modelData
      required property int index
      readonly property int _share: Math.floor(root._slack / Math.max(1, chips.count))
      width: implicitWidth + (index === chips.count - 1 ? root._slack - _share * (chips.count - 1) : _share)
      text: root.optionLabel(modelData)
      selected: root.optionValue(modelData) === root.value
      // Lit by the external panel cursor or by h/l while the group has Tab focus.
      hasCursor: root.cursorIndex === index
        || (root.activeFocus && root._focusedIndex === index)
      fontFamily: root.fontFamily
      fontSize: root.fontSize
      onClicked: root.changed(root.optionValue(modelData))
      onHovered: function(h) { root.hovered(index, h) }
    }
  }
}
