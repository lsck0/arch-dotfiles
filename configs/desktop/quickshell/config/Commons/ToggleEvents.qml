pragma Singleton
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  signal changed(string script)

  IpcHandler {
    target: "toggles"

    function changed(script: string): void { root.changed(script) }
  }
}
