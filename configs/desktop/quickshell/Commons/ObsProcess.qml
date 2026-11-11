pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
  id: root
  property bool running: false
  property bool probed: false
  property bool connected: false
  // streaming or recording: what is on screen may be on the stream (the desktop widgets censor themselves)
  property bool live: false
  readonly property bool listening: listenState.state === "on"
  readonly property string listenScript: listenState.path
  property var inputVolumes: ({})
  property var inputMutes: ({})

  signal commandRequested(var command)

  function send(command) {
    root.commandRequested(command)
  }

  function listenSet(on) {
    if (on !== root.listening) Quickshell.execDetached([root.listenScript, on ? "on" : "off"])
  }

  function probe() {
    if (!proc.running) proc.running = true
  }

  Component.onCompleted: root.probe()

  ToggleState {
    id: listenState
    script: "toggle-obs-listen.nu"
  }

  IpcHandler {
    function toggleListen(): void {
      root.listenSet(!root.listening)
    }

    function listen(on: bool): void {
      root.listenSet(on)
    }

    function listening(): string {
      return root.listening ? "on" : "off"
    }

    target: "obs"
  }

  Process {
    id: proc
    command: ["pgrep", "-x", "obs"]
    onExited: function(exitCode) {
      root.running = exitCode === 0
      root.probed = true
    }
  }

  Connections {
    function onValuesChanged() {
      root.probe()
    }

    target: ToplevelManager.toplevels
  }

  Timer {
    interval: 60000
    running: root.running
    repeat: true
    onTriggered: root.probe()
  }
}
