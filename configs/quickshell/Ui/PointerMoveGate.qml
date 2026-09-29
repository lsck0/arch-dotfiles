import QtQuick

// ignores hover churn from delegates moving under a still pointer
QtObject {
  id: root

  property Item referenceItem: null
  property real threshold: 1
  property bool primed: false
  property real lastX: 0
  property real lastY: 0

  function reset() {
    root.primed = false
    root.lastX = 0
    root.lastY = 0
  }

  function moved(item, mouse) {
    if (!item || !mouse) {
      root.reset()
      return false
    }

    var target = root.referenceItem || item
    var point = item.mapToItem(target, mouse.x, mouse.y)
    var firstSample = !root.primed
    var didMove = !firstSample
      && (Math.abs(point.x - root.lastX) > root.threshold || Math.abs(point.y - root.lastY) > root.threshold)

    if (firstSample || didMove) {
      root.lastX = point.x
      root.lastY = point.y
    }
    root.primed = true

    return didMove
  }
}
