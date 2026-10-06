import QtQuick
import qs.Commons

// holds a Cava refcount while alive
QtObject {
  id: root

  property bool _held: false

  function _sync(wanted) {
    if (wanted === _held) return
    _held = wanted
    Cava.refCount += wanted ? 1 : -1
  }

  Component.onCompleted: _sync(true)
  Component.onDestruction: _sync(false)
}
