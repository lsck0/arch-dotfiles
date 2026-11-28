import QtQuick

// the keyboard cursor of an overlay list: steps and pages clamp at the ends
QtObject {
  required property ListView list
  property real rowHeight: 0
  readonly property int pageRows: rowHeight > 0 ? Math.max(1, Math.floor((list.height + list.spacing) / (rowHeight + list.spacing))) : 1

  function clamp(index) { return Math.max(0, Math.min(index, list.count - 1)) }

  function step(from, delta) { return clamp(from + delta) }

  function page(from, delta) { return clamp(from + delta * pageRows) }
}
