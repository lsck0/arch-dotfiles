pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

// the shell's one BlueZ pairing agent (scripts/bluetooth-agent.py), shared by every bar's network panel. request is
// the open question bluez asked ({id, type, device, name, passkey}) or null; respond answers it. A request that
// arrives with no network panel open opens the main bar's.
Singleton {
  id: root

  property var request: null
  // network panels showing the request; none open: the request opens the main bar's
  property int viewers: 0
  readonly property bool running: agentProc.running

  // a display request only shows the code: nothing to answer, it ends with the pairing or a cancel
  readonly property bool needsAnswer: !!request && request.type.indexOf("display-") !== 0

  function respond(accept, value) {
    if (!request) return
    if (needsAnswer) agentProc.write(JSON.stringify({ id: request.id, accept: accept, value: value || "" }) + "\n")
    request = null
  }

  // a passkey or PIN shown for typing on the device stays until its pairing ends; bluez sends no message for that
  readonly property var requestDevice: request && !needsAnswer
    ? Bluetooth.devices.values.find(d => d.dbusPath === request.device) || null // qmllint disable missing-property
    : null
  Connections {
    target: root.requestDevice
    ignoreUnknownSignals: true
    function onPairingChanged() { if (!root.requestDevice.pairing) root.request = null }
    function onPairedChanged() { root.request = null }
  }

  // the agent runs while bluetoothd has an adapter; without one RegisterAgent fails and it retries on the next one
  readonly property bool wanted: !!Bluetooth.defaultAdapter // qmllint disable unresolved-type

  Process {
    id: agentProc
    running: root.wanted
    command: ["setpriv", "--pdeathsig", "TERM", Paths.script("bluetooth-agent.py")]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        var msg
        try { msg = JSON.parse(line) } catch (e) { return }
        if (msg.type === "ready") return
        if (msg.type === "cancel") { root.request = null; return }
        root.request = msg
        if (root.viewers === 0) Quickshell.execDetached(Paths.ipcCall("bar", "open", "network"))
      }
    }
    onExited: {
      root.request = null
      if (root.wanted) restart.restart()
    }
  }

  // bluetoothd restarting, or the adapter coming up after the agent tried: try again
  Timer {
    id: restart
    interval: 5000
    onTriggered: if (root.wanted && !agentProc.running) agentProc.running = true
  }
}
