pragma Singleton
import Quickshell
import Quickshell.Io

// toggles/lib.sh calls `toggles changed` after any toggle changes state, so readers refresh on the event instead of polling
Singleton {
  id: root

  signal changed()

  IpcHandler {
    target: "toggles"

    function changed(): void { root.changed() }
  }
}
