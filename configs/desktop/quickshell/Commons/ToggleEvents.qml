pragma Singleton
import Quickshell
import Quickshell.Io

// lib.nu calls `toggles changed <script>` after a toggle flips, so readers need not poll
Singleton {
  id: root

  signal changed(string script)

  IpcHandler {
    target: "toggles"

    function changed(script: string): void { root.changed(script) }
  }
}
