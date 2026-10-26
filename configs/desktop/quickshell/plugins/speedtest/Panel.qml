import QtQuick
import qs.Commons
import qs.Ui

// network and disk speed tests: one overlay, the summon payload's mode ("disk") picks the script and labels
Item {
  id: root

  property bool opened: false
  property bool disk: false
  readonly property var v: test.values

  function open(payload) {
    disk = payload && payload.mode === "disk"
    opened = true
    test.start()
  }

  KeyValueProcess {
    id: test
    command: [Paths.script(root.disk ? "disk-speedtest.nu" : "network-speedtest.nu")]
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
    error: test.error
    open: root.opened
    onCloseRequested: { root.opened = false; test.stop() }
    onRunAgainRequested: test.start()
  }
}
