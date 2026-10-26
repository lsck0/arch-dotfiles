import QtQuick

// Serial queue over the caller's Process: it runs runItem's item and calls done() from onExited.
QtObject {
  id: root

  property var items: []
  property bool running: false

  signal runItem(var item)

  function enqueue(item) {
    root.items = root.items.concat([item])
    root.runNext()
  }

  function runNext() {
    if (root.running || root.items.length === 0) return
    var next = root.items[0]
    root.items = root.items.slice(1)
    root.running = true
    root.runItem(next)
  }

  function done() {
    root.running = false
    root.runNext()
  }
}
