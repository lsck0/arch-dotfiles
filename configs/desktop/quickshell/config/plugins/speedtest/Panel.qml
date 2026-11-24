import QtQuick
import qs.Commons
import qs.Ui

// network and disk speed tests: one overlay, the summon payload's mode ("disk") picks the script and labels
Item {
  id: root

  property bool opened: false
  property bool disk: false
  property var v: ({})
  property string error: ""
  property bool wanted: false
  property bool queued: false
  // the requested mode; disk follows it only when a run starts, so labels always match the running script
  property bool nextDisk: false

  function open(payload) {
    nextDisk = !!(payload && payload.mode === "disk")
    opened = true
    if (test.running && nextDisk !== disk) {
      stop()
      queued = true
      return
    }
    start()
  }

  function start() {
    queued = test.running && !wanted
    if (test.running) return
    disk = nextDisk
    wanted = true
    v = {}
    error = ""
    test.run()
  }

  function stop() {
    wanted = false
    queued = false
    test.running = false
  }

  // the scripts print one JSON object per line; {error} carries a failure
  JsonProcess {
    id: test
    streaming: true
    command: [Paths.script(root.disk ? "disk-speedtest.nu" : "network-speedtest.nu")]
    onParsed: function (data) {
      root.v = Object.assign({}, root.v, data)
      if (data.error) root.error = data.error
    }
  }

  Connections {
    target: test.process
    function onExited(exitCode) {
      if (root.wanted && exitCode !== 0 && root.error === "") root.error = "exited with " + exitCode
      root.wanted = false
      if (root.queued) Qt.callLater(root.start)
    }
  }

  SpeedTestOverlay {
    fontFamily: Style.font.family
    name: "speedtest"
    title: (root.disk ? root.v.disk : root.v.name) || (root.disk ? "disk speed" : "speed test")
    leftLabel: root.disk ? "READ" : "DOWNLOAD"
    rightLabel: root.disk ? "WRITE" : "UPLOAD"
    unit: root.disk ? "MB/s" : "Mbps"
    scaleStops: root.disk ? [500, 1000, 2500, 5000, 10000, 15000] : [100, 250, 500, 1000, 2500, 5000, 10000]
    running: test.running
    leftValue: Number(root.disk ? root.v.read : root.v.down) || 0
    rightValue: Number(root.disk ? root.v.write : root.v.up) || 0
    leftLive: test.running && (root.disk ? root.v.write : root.v.up) === undefined
    rightLive: test.running && (root.disk ? root.v.write : root.v.up) !== undefined
    statusText: !root.disk && root.v.ping ? "PING " + root.v.ping + " ms" : ""
    error: root.error
    open: root.opened
    onCloseRequested: { root.opened = false; root.stop() }
    onRunAgainRequested: root.start()
  }
}
