import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "costs"

  property var hetzner: null
  property var cloudflare: null
  property var gcp: null

  readonly property bool anyConfigured: hetzner !== null || cloudflare !== null || gcp !== null
  // rough: currencies differ per provider
  readonly property real totalCost: (Number(hetzner) || 0) + (Number(cloudflare) || 0) + (Number(gcp) || 0)
  readonly property real maxCost: Math.max(Number(hetzner) || 0, Number(cloudflare) || 0, Number(gcp) || 0)

  property var costHist: []

  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  function refresh() {
    if (!costsProc.running) costsProc.running = true
  }

  Process {
    id: costsProc
    command: [Paths.barWidget("costs-fetch.sh")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text || "{}")
          root.hetzner = d.hetzner !== undefined ? d.hetzner : null
          root.cloudflare = d.cloudflare !== undefined ? d.cloudflare : null
          root.gcp = d.gcp !== undefined ? d.gcp : null
          if (root.anyConfigured) root.costHist = Util.historyPush(root.costHist, root.totalCost)
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
    tooltipText: root.anyConfigured ? "Cloud costs" : "Cloud costs: no credentials configured"
    onEntered: if (root.bar) root.bar.hoverOpen(root.moduleName)
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
  }

  component CostRow: Column {
    id: cr
    property string label: ""
    property var amount: null
    property string symbol: "$"
    width: parent ? parent.width : 0
    spacing: Style.spacing.xxs

    Row {
      width: cr.width
      Text {
        width: parent.width * 0.5
        text: cr.label
        color: Color.menu.text
        font.pixelSize: Style.font.caption
        font.family: Style.font.family
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Style.headerTracking * 0.4
      }
      Text {
        width: parent.width * 0.5
        horizontalAlignment: Text.AlignRight
        text: cr.amount !== null ? cr.symbol + Number(cr.amount).toFixed(2) + "/mo" : "not configured"
        color: Color.menu.text
        opacity: cr.amount !== null ? Style.emphasis.strong : Style.emphasis.faint
        font.pixelSize: Style.font.body
        font.family: Style.font.family
        font.letterSpacing: Style.displayTracking
        layer.enabled: Style.fx.glow > 0 && cr.amount !== null
        layer.effect: Glow {}
      }
    }
    BarGauge {
      width: cr.width
      height: Style.spacing.md
      segments: 20
      visible: cr.amount !== null
      value: cr.amount !== null && root.maxCost > 0 ? Number(cr.amount) / root.maxCost : 0
    }
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    title: "Cloud Costs"
    onOpened: root.refresh()
    implicitWidth: Style.panelWidth.narrow
    implicitHeight: content.implicitHeight + padding * 2 + titleInset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.sm

      Column {
        width: parent.width
        visible: root.anyConfigured
        spacing: Style.spacing.xs

        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text {
            anchors.bottom: heroNum.bottom
            anchors.bottomMargin: Math.round(Style.font.display * 0.15)
            textFormat: Text.PlainText
            text: "\u{f155}"
            color: Color.accent
            opacity: Style.emphasis.dim
            font.family: root.bar ? root.bar.iconFontFamily : Style.font.iconFamily
            font.pixelSize: Style.font.title
          }
          Text {
            id: heroNum
            anchors.bottom: parent.bottom
            text: root.totalCost.toFixed(2)
            color: Color.accent
            font.family: Style.font.family
            font.bold: true
            font.pixelSize: Math.round(Style.font.display * 1.4)
            font.letterSpacing: Style.displayTracking
            layer.enabled: Style.fx.glow > 0
            layer.effect: Glow {}
          }
          Text {
            anchors.bottom: heroNum.bottom
            anchors.bottomMargin: Math.round(Style.font.display * 0.35)
            text: "/ MO"
            color: Color.accent
            opacity: Style.emphasis.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Style.headerTracking
          }
        }
        // maxValue <= minValue means auto-scale
        Sparkline { width: parent.width; height: Style.space(30); values: root.costHist; minValue: 0; maxValue: 0; color: Color.accent }
      }

      PanelSectionHeader { text: "PER PROVIDER" }

      CostRow { label: "Hetzner"; amount: root.hetzner; symbol: "€" }
      CostRow { label: "Cloudflare"; amount: root.cloudflare; symbol: "$" }
      CostRow { label: "GCP"; amount: root.gcp; symbol: "$" }

      Text {
        visible: !root.anyConfigured
        width: parent.width
        wrapMode: Text.Wrap
        text: "Drop credentials in ~/.config/costs/, see costs-fetch.sh for what each provider needs"
        color: Color.menu.text
        opacity: Style.emphasis.faint
        font.pixelSize: Style.font.caption
        font.family: Style.font.family
      }
    }
  }
}
