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
    command: [Paths.script("network-speedtest.sh")]
  }

  SpeedTestOverlay {
    fontFamily: Style.font.family
    layerNamespace: "quickshell-network-speedtest"
    title: test.values.name || ""
    leftLabel: "DOWNLOAD"
    rightLabel: "UPLOAD"
    runAgainTooltip: "Measure again via fast.com"
    running: test.running
    leftValue: Number(test.values.down) || 0
    rightValue: Number(test.values.up) || 0
    leftLive: test.running && test.values.up === undefined
    rightLive: test.running && test.values.up !== undefined
    statusText: test.values.ping ? "PING " + test.values.ping + " ms" : ""
    error: test.error
    open: root.opened
    onCloseRequested: { root.opened = false; test.stop() }
    onRunAgainRequested: test.start()
  }
}
