import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property bool opened: false

  function open() {
    opened = true
    test.start()
  }

  KeyValueProcess {
    id: test
    command: [Paths.script("disk-speedtest.sh")]
  }

  SpeedTestOverlay {
    fontFamily: Style.font.family
    layerNamespace: "quickshell-disk-speedtest"
    title: test.values.disk || ""
    leftLabel: "READ"
    rightLabel: "WRITE"
    unit: "MB/s"
    scaleStops: [500, 1000, 2500, 5000, 10000, 15000]
    running: test.running
    leftValue: Number(test.values.read) || 0
    rightValue: Number(test.values.write) || 0
    leftLive: test.running && test.values.write === undefined
    rightLive: test.running && test.values.write !== undefined
    error: test.error
    open: root.opened
    onCloseRequested: { root.opened = false; test.stop() }
    onRunAgainRequested: test.start()
  }
}
