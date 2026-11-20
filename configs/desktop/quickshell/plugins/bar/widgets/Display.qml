pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "display"
  barPriority: 50
  hoverPanel: true
  hoverFill: true

  property real brightnessPct: 50
  property bool brightnessKnown: false
  property bool brightnessDragging: false
  property var monitors: []
  readonly property var activeMonitors: monitors.filter(function (m) { return !m.disabled })

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refreshAllBrightness() {
    for (const monitor of root.activeMonitors) {
      const proc = brightnessGetComponent.createObject(root, { monitorName: monitor.name }) as Process
      proc.running = true
    }
  }

  // A wheel spin or held key asks for many levels; one process sets every monitor in turn, and the newest asked
  // level follows once it exits. Detached sets per notch landed in any order, leaving an older level last. Pending and
  // applying are -1 when there is none, so a level asked again after a finished run always runs.
  property int brightnessPending: -1
  readonly property int brightnessStepPct: 5
  property int brightnessApplying: -1

  function applyBrightnessAll(pct) {
    pct = Math.max(1, Math.min(100, Math.round(pct)))
    root.brightnessPct = pct
    root.brightnessKnown = true
    root.brightnessPending = brightnessSet.running && pct === root.brightnessApplying ? -1 : pct
    root.brightnessFlush()
  }

  function brightnessFlush() {
    if (brightnessSet.running || root.brightnessPending < 0)
      return
    root.brightnessApplying = root.brightnessPending
    root.brightnessPending = -1
    const names = root.activeMonitors.map(function (m) { return m.name })
    brightnessSet.command = ["sh", "-c", 'pct="$1"; script="$2"; shift 2; for m; do "$script" set "$m" "$pct"; done',
      "sh", String(root.brightnessApplying), Paths.script("monitor-brightness.nu")].concat(names)
    brightnessSet.running = true
  }

  Process {
    id: brightnessSet
    onExited: {
      root.brightnessApplying = -1
      root.brightnessFlush()
    }
  }

  readonly property string gradingCli: Paths.dotfiles + "/configs/desktop/color-grading/color-grading.py"
  readonly property string shaderScript: Paths.toggle("toggle-shader.nu")
  property var grading: ({ preset: "", nightlight: false, presets: [] })
  property var shaders: ({ current: "off", shaders: [] })
  readonly property int colorMinAgeMs: 60 * 1000
  property real colorReadMs: 0

  function refreshColor() {
    root.colorReadMs = Date.now()
    gradingProc.run()
    shaderProc.run()
  }

  // a press while one runs waits its turn rather than being dropped
  property ProcessQueue colorQueue: ProcessQueue {
    onRunItem: function (argv) { colorActionProc.command = argv; colorActionProc.running = true }
  }
  function colorRun(argv) { root.colorQueue.enqueue(argv) }

  function shaderName(entry) { return String(entry).split(":")[0] }
  function shaderVariant(entry) { var i = String(entry).indexOf(":"); return i < 0 ? "" : String(entry).substring(i + 1) }

  JsonProcess {
    id: gradingProc
    command: [root.gradingCli, "status"]
    onParsed: function(data) { root.grading = data }
  }

  JsonProcess {
    id: shaderProc
    command: [root.shaderScript, "status"]
    onParsed: function(data) { root.shaders = data }
  }

  Process {
    id: colorActionProc
    onExited: {
      root.colorQueue.done()
      if (!root.colorQueue.running) root.refreshColor()
    }
  }

  // focus mode, settings and the menu change them too: re-read now while shown, else on the next open
  Connections {
    target: ToggleEvents
    function onChanged(script) {
      if (["toggle-nightlight.nu", "toggle-color-grading.nu", "toggle-shader.nu"].indexOf(script) < 0) return
      if (panel.visible) root.refreshColor()
      else root.colorReadMs = 0
    }
  }

  function setMonitorLayout(name, action) {
    var args = [Paths.toggle("toggle-monitor-scale.nu"), "layout", name]
    if (action.indexOf("mirror:") === 0) args.push("mirror", action.substring(7))
    else args.push(action)
    Quickshell.execDetached(args)
    monitorsSettle.restart()
  }

  Timer {
    id: monitorsSettle
    interval: 800
    onTriggered: monitorsProc.run()
  }

  readonly property var monitorScales: [1, 1.25, 1.5, 1.666667, 2]

  function setMonitorScale(name, scale) {
    Quickshell.execDetached([Paths.toggle("toggle-monitor-scale.nu"), "live", String(scale), name])
    monitorsSettle.restart()
  }

  Component {
    id: brightnessGetComponent
    Process {
      id: proc
      property string monitorName: ""
      command: [Paths.script("monitor-brightness.nu"), "get", monitorName]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          var pct = parseInt(String(text || "").trim(), 10)
          if (!isNaN(pct) && !root.brightnessDragging) {
            root.brightnessPct = pct
            root.brightnessKnown = true
          }
          proc.destroy()
        }
      }
    }
  }

  JsonProcess {
    id: monitorsProc
    command: ["hyprctl", "monitors", "all", "-j"]
    onParsed: function(data) {
      root.monitors = data
      if (!root.brightnessKnown) root.refreshAllBrightness()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "monitoradded" || event.name === "monitorremoved") monitorsProc.run()
    }
  }

  Component.onCompleted: monitorsProc.run()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u{f0379}"
    tooltipText: "Brightness " + (root.brightnessKnown ? Math.round(root.brightnessPct) + "%" : "--") + " :: scroll +-" + root.brightnessStepPct
    onWheelMoved: function(delta) {
      if (root.brightnessKnown && delta !== 0) root.applyBrightnessAll(root.brightnessPct + (delta > 0 ? 1 : -1) * root.brightnessStepPct)
    }
  }

  HoverPanel {
    id: panel
    anchorWidget: root
    implicitWidth: Style.panelWidth.normal

    onOpened: {
      monitorsProc.run()
      if (Date.now() - root.colorReadMs >= root.colorMinAgeMs) root.refreshColor()
      root.refreshAllBrightness()
    }

    title: "DISPLAY"

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.sm

      PanelSectionHeader { text: "BRIGHTNESS" }

      // the slider is the gauge; the monitor list below counts the monitors
      Fader {
        width: parent.width
        enabled: root.brightnessKnown
        muteable: false
        glyph: "\u{f0379}"
        minimum: 1
        maximum: 100
        integer: true
        step: root.brightnessStepPct
        value: root.brightnessPct
        readoutText: root.brightnessKnown ? Math.round(root.brightnessPct) + "%" : "--"
        onMoved: function(v) { root.brightnessDragging = true; root.brightnessPct = v }
        onReleased: function(v) { root.brightnessDragging = false; root.applyBrightnessAll(v) }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "MONITORS" }

      Repeater {
        model: root.monitors
        Column {
          id: monitorRow
          required property var modelData
          width: content.width
          spacing: Style.spacing.xs

          readonly property bool disabled: !!modelData.disabled
          readonly property string mirrorOf: modelData.mirrorOf && modelData.mirrorOf !== "none" ? modelData.mirrorOf : ""
          readonly property string layoutValue: disabled ? "off" : (mirrorOf ? "mirror:" + mirrorOf : "extend")

          Row {
            spacing: Style.spacing.sm
            Label {
              text: monitorRow.modelData.name
              color: Colors.menu.text
              caption: true
            }
            Label {
              text: monitorRow.disabled ? "off"
                : monitorRow.modelData.width + "x" + monitorRow.modelData.height + " :: " + Math.round(monitorRow.modelData.refreshRate) + " Hz"
                  + (monitorRow.mirrorOf ? " :: mirroring " + monitorRow.mirrorOf : "")
              dim: true
              caption: true
            }
          }

          ChoiceRow {
            visible: root.monitors.length > 1
            caption: "LAYOUT"
            options: {
              var opts = [{ value: "extend", label: "EXTEND" }]
              var others = 0
              for (let i = 0; i < root.monitors.length; i++) {
                const m = root.monitors[i]
                if (m.name === monitorRow.modelData.name || m.disabled) continue
                if (m.mirrorOf && m.mirrorOf !== "none") continue
                others++
                opts.push({ value: "mirror:" + m.name, label: "MIRROR " + m.name })
              }
              if (others > 0 || monitorRow.disabled) opts.push({ value: "off", label: "OFF" })
              return opts
            }
            value: monitorRow.layoutValue
            onChanged: function(v) { if (v !== monitorRow.layoutValue) root.setMonitorLayout(monitorRow.modelData.name, v) }
          }

          ChoiceRow {
            visible: !monitorRow.disabled
            caption: "SCALE"
            options: root.monitorScales.map(function(s) { return { value: String(s), label: (Math.round(s * 100) / 100) + "x" } })
            value: {
              const current = root.monitorScales.find(s => Math.abs(Number(monitorRow.modelData.scale) - s) < 0.01)
              return current === undefined ? "" : String(current)
            }
            onChanged: function(v) { root.setMonitorScale(monitorRow.modelData.name, Number(v)) }
          }
        }
      }

      // a pause first: the click's own pointer motion would wake them (misc:mouse_move_enables_dpms)
      PanelRow {
        width: parent.width
        label: "Screens off"
        trailing: "until input"
        onActivated: {
          root.closePanel()
          Quickshell.execDetached(["sh", "-c", "sleep 1.5; exec \"$0\" off", Paths.home + "/.config/hypr/dpms.nu"])
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "COLOR GRADING" }

      Column {
        width: parent.width
        spacing: Style.spacing.xxs

        // one preset at a time, like the firewall and route modes: a segmented row instead of a row per preset
        ButtonGroup {
          visible: options.length > 0
          width: parent.width
          fill: true
          spacing: Style.spacing.xs
          options: (root.grading.presets || []).map(function(p) { return { value: p.name, label: String(p.label).toUpperCase() } })
          value: root.grading.preset
          onChanged: function(v) { if (v !== root.grading.preset) root.colorRun([Paths.toggle("toggle-color-grading.nu"), "set", v]) }
        }

        PanelRow {
          width: parent.width
          stateMarker: true
          on: root.grading.nightlight === true
          label: "Night light"
          onActivated: root.colorRun([Paths.toggle("toggle-nightlight.nu"), "toggle"])
        }
      }

      PanelSeparator { visible: shaderList.visible }
      PanelSectionHeader { visible: shaderList.visible; text: "SHADERS" }

      Column {
        id: shaderList
        visible: (root.shaders.shaders || []).length > 0
        width: parent.width
        spacing: Style.spacing.xxs

        // no "Off" row: the active shader's own row turns it off
        Repeater {
          model: root.shaders.shaders || []
          Column {
            id: shaderItem
            required property var modelData
            readonly property bool active: root.shaderName(root.shaders.current) === modelData.name
            width: parent.width
            spacing: Style.spacing.xxs

            PanelRow {
              width: parent.width
              stateMarker: true
              on: shaderItem.active
              label: shaderItem.modelData.label
              onActivated: root.colorRun(shaderItem.active ? [root.shaderScript, "off"] : [root.shaderScript, "set", shaderItem.modelData.name])
            }

            // the variants of the running shader only: activating its row starts the first one
            ButtonGroup {
              visible: shaderItem.active && shaderItem.modelData.variants.length > 0
              width: parent.width
              fill: true
              spacing: Style.spacing.xs
              options: shaderItem.modelData.variants.map(function(v) { return { value: v, label: v.toUpperCase() } })
              value: shaderItem.active ? root.shaderVariant(root.shaders.current) : ""
              onChanged: function(v) { root.colorRun([root.shaderScript, "set", shaderItem.modelData.name + ":" + v]) }
            }
          }
        }
      }
    }
  }

  // a caption naming the choice, then its chips, wrapping under themselves past the panel's width
  component ChoiceRow: Item {
    id: choice
    property string caption: ""
    property alias options: group.options
    property alias value: group.value

    signal changed(string value)

    width: parent ? parent.width : 0
    implicitHeight: group.implicitHeight

    Label {
      id: choiceCaption
      width: Style.space(52)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: choice.caption
      dim: true
      caption: true
    }

    ButtonGroup {
      id: group
      anchors.left: choiceCaption.right
      anchors.right: parent.right
      spacing: Style.spacing.xs
      onChanged: function(v) { choice.changed(v) }
    }
  }
}
