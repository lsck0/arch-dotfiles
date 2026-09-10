import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell. Was blocked on missing credentials —
// scaffolded so it's ready the moment real tokens exist. Drop them at:
//   ~/.config/costs/hetzner_token        (Hetzner Cloud API token)
//   ~/.config/costs/cloudflare_token     (needs Enterprise plan for billing API)
//   ~/.config/costs/gcp_billing_sa.json  (service account + BigQuery export)
// None of these live in git (not this repo, not the configs/secrets
// submodule) — see costs-fetch.sh for exactly what each one needs.
BarWidget {
  id: root
  moduleName: "costs"

  property var hetzner: null
  property var cloudflare: null
  property var gcp: null

  readonly property bool anyConfigured: hetzner !== null || cloudflare !== null || gcp !== null

  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  function refresh() {
    if (!costsProc.running) costsProc.running = true
  }

  Process {
    id: costsProc
    command: [Quickshell.env("HOME") + "/projects/arch-dotfiles/configs/quickshell/plugins/bar/widgets/costs-fetch.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text || "{}")
          root.hetzner = d.hetzner !== undefined ? d.hetzner : null
          root.cloudflare = d.cloudflare !== undefined ? d.cloudflare : null
          root.gcp = d.gcp !== undefined ? d.gcp : null
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: 60 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u{f155}"
    tooltipText: root.anyConfigured ? "Cloud costs" : "Cloud costs — no credentials configured"
    onEntered: { root.bar.hoverOpen(root.moduleName); root.refresh() }
    onExited: root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    implicitWidth: Style.space(300) + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.sm

      Text { text: "Cloud costs"; color: Color.menu.text; opacity: 0.6; font.pixelSize: Style.font.caption; font.family: Style.font.family }

      Row {
        width: content.width
        Text { width: parent.width * 0.5; text: "Hetzner"; color: Color.menu.text; font.pixelSize: Style.font.body; font.family: Style.font.family }
        Text {
          width: parent.width * 0.5
          horizontalAlignment: Text.AlignRight
          text: root.hetzner !== null ? "€" + root.hetzner.toFixed(2) + "/mo" : "not configured"
          color: root.hetzner !== null ? Color.menu.text : Color.menu.text
          opacity: root.hetzner !== null ? 1 : 0.4
          font.pixelSize: Style.font.body
          font.family: Style.font.family
        }
      }
      Row {
        width: content.width
        Text { width: parent.width * 0.5; text: "Cloudflare"; color: Color.menu.text; font.pixelSize: Style.font.body; font.family: Style.font.family }
        Text {
          width: parent.width * 0.5
          horizontalAlignment: Text.AlignRight
          text: root.cloudflare !== null ? "$" + root.cloudflare.toFixed(2) + "/mo" : "not configured"
          opacity: root.cloudflare !== null ? 1 : 0.4
          color: Color.menu.text
          font.pixelSize: Style.font.body
          font.family: Style.font.family
        }
      }
      Row {
        width: content.width
        Text { width: parent.width * 0.5; text: "GCP"; color: Color.menu.text; font.pixelSize: Style.font.body; font.family: Style.font.family }
        Text {
          width: parent.width * 0.5
          horizontalAlignment: Text.AlignRight
          text: root.gcp !== null ? "$" + root.gcp.toFixed(2) + "/mo" : "not configured"
          opacity: root.gcp !== null ? 1 : 0.4
          color: Color.menu.text
          font.pixelSize: Style.font.body
          font.family: Style.font.family
        }
      }

      Text {
        visible: !root.anyConfigured
        width: parent.width
        wrapMode: Text.Wrap
        text: "Drop credentials in ~/.config/costs/ — see costs-fetch.sh for what each provider needs"
        color: Color.menu.text
        opacity: 0.4
        font.pixelSize: Style.font.caption
        font.family: Style.font.family
      }
    }
  }
}
