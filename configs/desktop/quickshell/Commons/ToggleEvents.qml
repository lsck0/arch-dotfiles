pragma Singleton
import Quickshell
import Quickshell.Io

// scripts/toggles/lib.sh calls `toggles changed <script>` after any toggle changes state, so readers refresh on the event instead of polling
Singleton {
  id: root

  signal changed(string script)

  IpcHandler {
    target: "toggles"

    function changed(script: string): void { root.changed(script) }
  }
}
