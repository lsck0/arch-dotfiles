import QtQuick
import qs.Commons

// A held reference to the Cava singleton's subprocess.
QtObject {
  id: root

  property bool active: true
  property bool _held: false

  function _sync(wanted) {
    if (wanted === _held) return
    _held = wanted
    Cava.refCount += wanted ? 1 : -1
  }

  onActiveChanged: _sync(active)
  Component.onCompleted: _sync(active)
  Component.onDestruction: _sync(false)
}
