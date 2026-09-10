import QtQuick
import qs.Commons

// A held reference to the Cava singleton's subprocess. Instantiate one (via
// a Loader whose `active` tracks "do I actually need spectrum data right
// now") and cava runs; destroy it and the count drops back.
//
// The point of a component rather than bare `Cava.refCount++` at the call
// site is Component.onDestruction: a widget that is torn down mid-playback
// (bar reconfigured, panel closed, screen removed) must give its reference
// back, and doing that by hand is exactly the bookkeeping everyone forgets.
// Leak one and cava runs forever; double-release and it stops while
// something is still watching.
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
