pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "agents"
  barPriority: 15
  hoverPanel: true
  hoverFill: true

  property bool received: false
  property var usage: ({})
  property string errorText: ""
  property real updatedMs: 0
  readonly property int staleAfterMs: usageProc.intervalMs * 2

  // some plans have no 5h session window: the api sends no session header, the script a dash
  readonly property bool hasSession: typeof usage.u_session === "number"
  readonly property int sessionPct: hasSession ? usage.u_session : 0
  readonly property int weekPct: Number(usage.u_week) || 0
  readonly property int worstPct: Math.max(sessionPct, weekPct)
  readonly property int worstPctShown: Math.min(100, worstPct)
  readonly property string worstWhich: hasSession && sessionPct >= weekPct ? "S" : "W"
  readonly property bool tight: worstPct >= 80
  readonly property bool hasUsage: usage.t_total !== undefined && usage.t_total !== ""
  readonly property var models: [
    { name: usage.m1_name, tokens: usage.m1_tokens, cost: usage.m1_cost },
    { name: usage.m2_name, tokens: usage.m2_tokens, cost: usage.m2_cost },
    { name: usage.m3_name, tokens: usage.m3_tokens, cost: usage.m3_cost }
  ].filter(function(m) { return m.name })

  // the session reset in the shell's own clock format; a day prefix once it is not today
  readonly property string sessionResetText: {
    const at = Number(usage.u_reset_at) || 0
    if (at <= 0) return usage.u_reset || ""
    const when = new Date(at * 1000)
    const sameDay = when.toDateString() === new Date().toDateString()
    return Qt.formatDateTime(when, sameDay ? Util.timeFormat : Util.dayFormat + " " + Util.timeFormat)
  }

  visible: hasUsage || errorText !== ""

  implicitWidth: trigger.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: Style.bar.sizeHorizontal

  JsonProcess {
    id: usageProc
    command: [Paths.barWidget("agent-usage.nu")]
    intervalMs: 45 * 60 * 1000
    minAgeMs: 60 * 1000
    onParsed: function (data) {
      root.received = true
      root.errorText = data && data.error ? String(data.error) : ""
      if (root.errorText) return
      root.usage = data
      if (!root.hasUsage) return
      root.updatedMs = Date.now()
    }
    onFailed: function (error) { root.received = true; root.errorText = "bad json" }
  }

  Row {
    id: trigger
    anchors.centerIn: parent
    spacing: Style.spacing.xs

    Label {
      anchors.verticalCenter: parent.verticalCenter
      text: "\u{ee0d}"
      color: root.tight ? Colors.urgent : Colors.bar.text
      icon: true
      font.pixelSize: Style.font.icon
    }
    Label {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.hasUsage
      text: root.worstWhich + " " + root.worstPctShown + "%"
      color: root.tight ? Colors.urgentText : Colors.bar.text
      font.letterSpacing: Style.displayTracking
      layer.enabled: Style.fx.glow > 0
      layer.effect: Glow { shadowColor: root.tight ? Colors.urgent : Style.fx.glowColor }
    }
    DataState {
      anchors.verticalCenter: parent.verticalCenter
      loading: usageProc.running
      error: root.errorText
      updatedMs: root.updatedMs
      staleAfterMs: root.staleAfterMs
    }
  }

  HoverPanel {
    anchorWidget: root
    title: "CLAUDE CODE"
    onOpened: usageProc.refresh()
    implicitWidth: Style.panelWidth.normal

    Column {
      width: parent.width
      spacing: Style.spacing.sm

      StatRow {
        // a failed refresh shows over older data too: the figures below are then the last good ones
        visible: !root.received || root.errorText !== ""
        label: "Status"
        value: root.errorText ? "x ERR " + root.errorText : "--"
        valueColor: root.errorText !== "" ? Colors.urgentText : Colors.menu.text
      }

      Column {
        width: parent.width
        visible: root.hasUsage
        spacing: Style.spacing.sm

        // the bar's worst figure is the larger of these two rows
        PanelSectionHeader { text: "Limits" }
        StatRow {
          visible: !!root.usage.sub
          label: "Plan"
          value: root.usage.sub ? root.usage.sub + " " + (root.usage.tier || "") : ""
        }
        MetricRow {
          visible: root.hasSession
          valueBeside: true
          label: "Session"
          value: root.sessionPct + "%"
          note: root.sessionResetText ? "resets " + root.sessionResetText : ""
          fraction: Math.min(1, root.sessionPct / 100)
          tint: root.sessionPct >= 80 ? Colors.urgent : Colors.accent
        }
        MetricRow {
          valueBeside: true
          label: "7D"
          value: root.weekPct + "%"
          fraction: Math.min(1, root.weekPct / 100)
          tint: root.weekPct >= 80 ? Colors.urgent : Colors.accent
        }

        PanelSeparator {}
        PanelSectionHeader { text: "Today" }
        StatRow { label: "Tokens"; value: root.usage.t_total || "--"; note: root.usage.t_cost || "" }
        StatRow { label: "In / out"; value: (root.usage.t_input || "--") + " / " + (root.usage.t_output || "--") }
        StatRow { label: "Cache r/w"; value: (root.usage.t_cache_r || "--") + " / " + (root.usage.t_cache_w || "--") }
        StatRow {
          label: "Messages"
          value: String(root.usage.t_messages === undefined ? "--" : root.usage.t_messages)
          note: Util.count(root.usage.t_sessions || 0, "session")
        }
        StatRow {
          visible: (root.usage.active || 0) > 0
          label: "Active now"
          value: String(root.usage.active)
        }

        PanelSeparator {}
        PanelSectionHeader { text: "Week" }
        StatRow { label: "Tokens"; value: root.usage.w_tokens || "--"; note: root.usage.w_cost || "" }
        StatRow {
          label: "Messages"
          value: String(root.usage.w_messages === undefined ? "--" : root.usage.w_messages)
          note: Util.count(root.usage.w_sessions || 0, "session")
        }
        StatRow {
          label: "Daily"
          value: root.usage.spark || ""
          note: (root.usage.streak || 0) + "d streak"
        }
        StatRow {
          visible: !!root.usage.top_project
          label: "Top project"
          value: root.usage.top_project || ""
        }

        Column {
          width: parent.width
          visible: root.models.length > 0
          spacing: Style.spacing.sm

          PanelSeparator {}
          PanelSectionHeader { text: root.usage.m_days ? "Models :: " + root.usage.m_days + "d" : "Models" }
          Repeater {
            model: root.models
            delegate: StatRow {
              required property var modelData
              label: modelData.name
              value: modelData.tokens
              note: modelData.cost
            }
          }
        }

        StatRow {
          visible: root.updatedMs > 0
          label: "Updated"
          value: root.updatedMs > 0 ? Qt.formatDateTime(new Date(root.updatedMs), Util.dayFormat + " " + Util.timeFormat) : ""
        }
      }
    }
  }
}
