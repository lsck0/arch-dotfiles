import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// claude code usage, same payload as the trmnl display
BarWidget {
  id: root
  moduleName: "agents"

  property bool received: false
  property var usage: ({})

  readonly property int sessionPct: Number(usage.u_session) || 0
  readonly property int weekPct: Number(usage.u_week) || 0
  readonly property int worstPct: Math.max(sessionPct, weekPct)
  // api can report over 100 once a limit is hit
  readonly property int worstPctShown: Math.min(100, worstPct)
  readonly property string worstWhich: sessionPct >= weekPct ? "S" : "W"
  readonly property bool tight: worstPct >= 80
  readonly property bool hasUsage: usage.t_total !== undefined && usage.t_total !== ""
  readonly property var models: [
    { name: usage.m1_name, tokens: usage.m1_tokens, pct: Number(usage.m1_pct) || 0, cost: usage.m1_cost },
    { name: usage.m2_name, tokens: usage.m2_tokens, pct: Number(usage.m2_pct) || 0, cost: usage.m2_cost },
    { name: usage.m3_name, tokens: usage.m3_tokens, pct: Number(usage.m3_pct) || 0, cost: usage.m3_cost }
  ].filter(function(m) { return m.name })

  property var pctHist: []

  visible: hasUsage

  implicitWidth: trigger.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  function refresh() {
    if (!usageProc.running) usageProc.running = true
  }

  Process {
    id: usageProc
    command: [Paths.barWidget("agent-usage.py")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.usage = JSON.parse(text || "{}")
          root.received = true
          if (root.hasUsage) root.pctHist = Util.historyPush(root.pctHist, root.worstPct)
        } catch (e) {}
      }
    }
  }

  // each poll costs an api request
  Timer {
    interval: 10 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: mouseArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  Row {
    id: trigger
    anchors.centerIn: parent
    spacing: Style.spacing.sm

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "\u{ee0d}"
      color: root.tight ? Color.urgent : (root.bar ? root.bar.barForeground : Color.foreground)
      font.family: root.bar ? root.bar.iconFontFamily : Style.font.iconFamily
      font.pixelSize: Style.font.icon
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.worstWhich + " " + root.worstPctShown + "%"
      color: root.tight ? Color.urgent : (root.bar ? root.bar.barForeground : Color.foreground)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.letterSpacing: Style.displayTracking
      layer.enabled: Style.fx.glow > 0
      layer.effect: Glow { shadowColor: root.tight ? Color.urgent : Style.fx.glowColor }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    onEntered: if (root.bar) root.bar.hoverOpen(root.moduleName)
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
  }

  component BarRow: Item {
    id: barRow
    property string label: ""
    property string value: ""
    property string note: ""
    // -1 draws no bar
    property int pct: -1
    property bool alert: false
    width: parent.width
    implicitHeight: rowValue.implicitHeight + Style.spacing.xxs * 2

    Rectangle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      visible: barRow.pct >= 0
      height: parent.height
      width: parent.width * Math.max(0, Math.min(100, barRow.pct)) / 100
      radius: Style.cornerRadius
      color: barRow.alert ? Util.alpha(Color.urgent, 0.18) : Util.alpha(Color.accent, 0.15)
    }
    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width * 0.4
      text: barRow.label
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.sm
      Text {
        id: rowValue
        text: barRow.value
        color: barRow.alert ? Color.urgent : Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      Text {
        visible: barRow.note !== ""
        text: barRow.note
        color: Color.menu.text
        opacity: Style.emphasis.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  component Hero: Row {
    id: hero
    property int pct: 0
    property color tint: Color.accent
    spacing: Style.spacing.xxs
    Text {
      id: heroNum
      anchors.bottom: parent.bottom
      text: hero.pct
      color: hero.tint
      font.family: Style.font.family
      font.pixelSize: Math.round(Style.font.display * 1.7)
      font.bold: true
      font.letterSpacing: Style.displayTracking
      layer.enabled: Style.fx.glow > 0
      layer.effect: Glow { shadowColor: hero.tint }
    }
    Text {
      anchors.bottom: heroNum.bottom
      anchors.bottomMargin: Math.round(Style.font.display * 0.35)
      text: "%"
      color: hero.tint
      opacity: Style.emphasis.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.title
    }
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    title: "Claude Code"
    implicitWidth: Style.panelWidth.normal
    implicitHeight: content.implicitHeight + padding * 2 + titleInset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

      BarRow {
        visible: !root.received
        label: "Status"
        value: "Reading usage..."
      }

      Column {
        width: parent.width
        visible: root.hasUsage
        spacing: Style.spacing.xs

        Item {
          width: parent.width
          implicitHeight: Math.max(usageHero.implicitHeight, usageSide.implicitHeight)
          height: implicitHeight
          Hero {
            id: usageHero
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            pct: root.worstPctShown
            tint: root.tight ? Color.urgent : Color.accent
          }
          Column {
            id: usageSide
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.56
            spacing: Style.spacing.xxs
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignRight
              visible: !!root.usage.sub
              text: root.usage.sub ? root.usage.sub + " " + (root.usage.tier || "") : ""
              color: Color.menu.text
              opacity: Style.emphasis.dim
              textFormat: Text.PlainText
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignRight
              text: "SESSION " + root.sessionPct + "% :: WEEK " + root.weekPct + "%"
              color: root.tight ? Color.urgent : Color.menu.text
              opacity: Style.emphasis.faint
              textFormat: Text.PlainText
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: Style.headerTracking * 0.4
            }
          }
        }
        Sparkline { width: parent.width; height: Style.space(34); values: root.pctHist; minValue: 0; maxValue: 100; color: root.tight ? Color.urgent : Color.accent }
        BarGauge { width: parent.width; height: Style.spacing.md; segments: 24; value: root.worstPct / 100; color: root.tight ? Color.urgent : Color.accent }
      }

      Column {
        width: parent.width
        visible: root.hasUsage
        spacing: Style.spacing.md

        PanelSectionHeader { text: "Limits" }
        BarRow {
          label: "Session"
          value: root.sessionPct + "%"
          note: root.usage.u_reset ? "resets " + root.usage.u_reset : ""
          pct: root.sessionPct
          alert: root.sessionPct >= 80
        }
        BarRow {
          label: "Week"
          value: root.weekPct + "%"
          pct: root.weekPct
          alert: root.weekPct >= 80
        }
        BarRow {
          // only present when the tui was scraped
          visible: root.usage.u_sonnet !== undefined && root.usage.u_sonnet !== "—"
          label: root.usage.u_model || "Model"
          value: root.usage.u_sonnet + "%"
          pct: Number(root.usage.u_sonnet) || 0
        }

        PanelSeparator {}
        PanelSectionHeader { text: "Today" }
        BarRow { label: "Tokens"; value: root.usage.t_total || "–"; note: root.usage.t_cost || "" }
        BarRow { label: "In / out"; value: (root.usage.t_input || "–") + " / " + (root.usage.t_output || "–") }
        BarRow { label: "Cache r/w"; value: (root.usage.t_cache_r || "–") + " / " + (root.usage.t_cache_w || "–") }
        BarRow {
          label: "Messages"
          value: String(root.usage.t_messages === undefined ? "–" : root.usage.t_messages)
          note: (root.usage.t_sessions || 0) + " sessions"
        }
        BarRow {
          visible: (root.usage.active || 0) > 0
          label: "Active now"
          value: String(root.usage.active)
          note: root.usage.fleet || ""
        }

        PanelSeparator {}
        PanelSectionHeader { text: "Week" }
        BarRow { label: "Tokens"; value: root.usage.w_tokens || "–"; note: root.usage.w_cost || "" }
        BarRow {
          label: "Messages"
          value: String(root.usage.w_messages === undefined ? "–" : root.usage.w_messages)
          note: (root.usage.w_sessions || 0) + " sessions"
        }
        BarRow {
          label: "Daily"
          value: root.usage.spark || ""
          note: (root.usage.streak || 0) + "d streak"
        }
        BarRow {
          visible: !!root.usage.top_project
          label: "Top project"
          value: root.usage.top_project || ""
        }

        Column {
          width: parent.width
          visible: root.models.length > 0
          spacing: Style.spacing.md

          PanelSeparator {}
          PanelSectionHeader { text: "Models" }
          Repeater {
            model: root.models
            delegate: BarRow {
              required property var modelData
              label: modelData.name
              value: modelData.tokens
              note: modelData.cost
              pct: modelData.pct
            }
          }
        }

        BarRow {
          visible: !!root.usage.updated
          label: "Updated"
          value: root.usage.updated || ""
        }
      }
    }
  }
}
