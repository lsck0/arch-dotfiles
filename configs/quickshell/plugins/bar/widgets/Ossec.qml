import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// OSSEC HIDS alerts in the bar.
BarWidget {
  id: root
  moduleName: "ossec"

  property bool received: false
  property bool ok: false
  property int total: 0
  property int high: 0
  property int maxLevel: 0
  property var recent: []

  function tip() {
    if (!root.received) return "OSSEC: loading..."
    if (!root.ok) return "OSSEC: alert log unreadable"
    if (root.total === 0) return "OSSEC: no alerts in the last 24h"
    var head = "OSSEC: " + root.total + " alerts / 24h · max level " + root.maxLevel
    var lines = root.recent.map(function(a) {
      return a.t + "  L" + a.level + "  rule " + a.rule + "  " + a.desc
    })
    return head + "\n" + lines.join("\n")
  }

  function openLog() {
    Quickshell.execDetached(["ghostty", "-e", "bash", "-lc",
      "sudo -n tail -n 200 -f /var/lib/ossec-hids/logs/alerts/alerts.log"])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: proc
    running: true
    command: [Paths.barWidget("ossec-alerts.py")]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        if (!line) return
        try {
          var s = JSON.parse(line)
          root.received = true
          root.ok = s.ok === true
          if (!root.ok) return
          root.total = s.total || 0
          root.high = s.high || 0
          root.maxLevel = s.maxLevel || 0
          root.recent = s.recent || []
        } catch (e) {}
      }
    }
  }

  // Urgent neon backlight bleeding out from behind the shield while a high-level alert is live.
  Rectangle {
    anchors.centerIn: parent
    width: Style.bar.iconCanvas
    height: width
    radius: width / 2
    color: Color.urgent
    visible: Style.fx.glow > 0 && root.ok && root.high > 0
    opacity: Style.fx.glowAlpha(0.9)
    layer.enabled: Style.fx.glow > 0
    layer.effect: MultiEffect {
      blurEnabled: true
      blur: 1.0
      blurMax: Style.fx.glowRadius
      autoPaddingEnabled: true
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-shield_alert
    text: "\u{f0ce4}"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    // urgent (activeColor) when a high-level alert is live, dimmed otherwise
    active: root.ok && root.high > 0
    dimmed: !active
    tooltipText: root.tip()
    onPressed: root.openLog()
  }
}
