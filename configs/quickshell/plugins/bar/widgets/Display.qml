import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell. Monitor scale changes at runtime go
// through `hyprctl eval` executing the Lua `hl.monitor({...})` table
// constructor (via scripts/set-monitor-scale.sh) — this Hyprland config is
// loaded through the non-legacy Lua parser (configs/hyprland/*.lua), and
// `hyprctl keyword monitor ...` unconditionally refuses to run under it
// ("keyword can't work with non-legacy parsers"), which is why the scale
// buttons used to silently do nothing. Runtime-only, not persisted to
// hyprland_monitors.lua, so a bad choice is reversible with `hyprctl
// reload` rather than editing the actual config.
//
// Brightness is ONE slider driving every connected monitor together, not
// one slider per output. Each output is still addressed individually on the
// backend (brightnessctl for the laptop panel, ddcutil per-bus for external
// DP/HDMI monitors — see scripts/monitor-brightness.sh for why), but the
// panel only ever shows a single control: a bar with per-monitor sliders
// that all move together the instant you touch one is not "one slider", and
// this desktop's whole point is two identical panels that stay in sync.
//
// The backend call (ddcutil over DDC/CI) is the slow part — tens to
// hundreds of ms per monitor even with the --bus fast path — so it is NOT
// invoked on every pointer-move tick while dragging. PanelSlider already
// separates its instantly-updating drag position (`liveValue`, driving the
// visible fill/knob) from the committed `value`; `onMoved` only updates the
// local `brightnessPct` (paints instantly, zero backend cost) and the
// actual ddcutil/brightnessctl calls fire once, from `onReleased`. That is
// the fix for the reported lag/flicker: previously every mouse-move fired a
// Quickshell.execDetached per monitor per pixel of drag.
BarWidget {
  id: root
  moduleName: "display"

  // Per-monitor state is still tracked (needed to know which outputs exist
  // and to seed the slider from the hardware's actual current value), but
  // the UI only ever surfaces one aggregate number.
  property var brightnessByMonitor: ({})
  property real brightnessPct: 50
  // Seeded once from the first `get` that comes back, so the initial poll
  // populating brightnessByMonitor doesn't fight a value the user is
  // actively dragging, and two monitors with slightly different starting
  // brightness don't make the slider jump after the first paints.
  property bool brightnessSeeded: false
  // `monitors all`, so disabled outputs stay listed and can be turned back on.
  property var monitors: []
  readonly property var activeMonitors: monitors.filter(function (m) { return !m.disabled })
  // Read from toggle-font.sh's own `shortlist`, not listed again here. The
  // panel used to carry a hardcoded four of the script's six, so the chip row
  // and the keybind that cycles the same setting disagreed about which fonts
  // exist — and the script already filters to what is actually installed,
  // which a literal cannot.
  property var fontChoices: []
  readonly property var fontSizes: [12, 13, 14, 16, 18]

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refreshBrightnessFor(name) {
    var proc = brightnessGetComponent.createObject(root, { monitorName: name })
    proc.running = true
  }

  function refreshAllBrightness() {
    for (var i = 0; i < root.activeMonitors.length; i++)
      root.refreshBrightnessFor(root.activeMonitors[i].name)
  }

  function setBrightnessFor(name, pct) {
    pct = Math.max(1, Math.min(100, Math.round(pct)))
    var copy = Object.assign({}, root.brightnessByMonitor)
    copy[name] = pct
    root.brightnessByMonitor = copy
    Quickshell.execDetached([Paths.shellScripts + "/monitor-brightness.sh", "set", name, String(pct)])
  }

  // The one place that actually talks to hardware. Called once per commit
  // (slider release, or a wheel tick, both of which fire `released` exactly
  // once) rather than per drag tick — see the header comment on why.
  function applyBrightnessAll(pct) {
    pct = Math.max(1, Math.min(100, Math.round(pct)))
    root.brightnessPct = pct
    for (var i = 0; i < root.activeMonitors.length; i++)
      root.setBrightnessFor(root.activeMonitors[i].name, pct)
  }

  function refreshMonitors() {
    if (!monitorsProc.running) monitorsProc.running = true
  }

  function openWallpaperPicker() {
    // `wallpaper-picker`, NOT switch-wallpaper.sh. With no arguments that
    // script falls through to an fzf+chafa picker, which needs a terminal —
    // launched detached from the shell it has no tty, so this button ran a
    // program that immediately gave up and nothing appeared. wallpaper-picker
    // is the wrapper that summons the native overlay, and it is the only
    // caller that passes `showLabels: true`, which is what puts the wallpaper
    // name under the selection.
    Quickshell.execDetached([Paths.shellScripts + "/wallpaper-picker.sh"])
  }

  // FONT CHANGES GO THROUGH toggles/toggle-font.sh, like every other state
  // change in this repo.
  //
  // These two used to be `sed -i` calls written out inline here, reaching into
  // ~/.config/ghostty and ~/.config/zed from a QML widget. toggle-font.sh was
  // written specifically to replace them (its header says so) and then this
  // file was never switched over, so the panel kept the old half-a-job copy:
  // it missed zed's terminal `font_family`, emacs, nvim, discord, spotify, GTK
  // and Qt/KDE entirely, and — the visible symptom — it never touched
  // quickshell's own theme.json, so the chip highlight below (which compares
  // against Style.fontFamily) could never light up for the family you just
  // picked. The script covers all of them and validates that the family is
  // actually installed before writing anything.
  function setFont(family) {
    Quickshell.execDetached([root.fontScript, "set", family])
    fontSettle.restart()
  }

  function setFontSize(size) {
    Quickshell.execDetached([root.fontScript, "set-size", String(size)])
    fontSettle.restart()
  }

  readonly property string fontScript: Paths.toggle("toggle-font.sh")

  // The family is readable straight off the live theme; the SIZE shown here is
  // the terminal/editor size (toggle-font.sh's reference value), which is not
  // the same number as quickshell's own base size, so it has to be asked for.
  property int currentFontSize: 0

  function refreshFontSize() {
    if (!fontSizeProc.running) fontSizeProc.running = true
  }

  Process {
    id: fontSizeProc
    command: [root.fontScript, "size"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var n = parseInt(String(text || "").trim(), 10)
        if (!isNaN(n)) root.currentFontSize = n
      }
    }
  }

  // The installed families are fixed for the session — fonts are not installed
  // while the shell is up — so this reads once at startup rather than per open.
  Process {
    id: fontListProc
    command: [root.fontScript, "shortlist"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var families = String(text || "").split("\n").filter(function (line) {
          return line.trim().length > 0
        })
        if (families.length > 0) root.fontChoices = families
      }
    }
  }

  // The script rewrites a dozen files and only then does quickshell's own
  // theme.json land; re-read once it has had a moment, so the selected chip
  // moves on its own rather than on the next hover.
  Timer {
    id: fontSettle
    interval: 600
    onTriggered: root.refreshFontSize()
  }

  // action: "extend", "off", or "mirror:<source output>".
  function setMonitorLayout(name, action) {
    var args = [Paths.shellScripts + "/set-monitor-layout.sh", name]
    if (action.indexOf("mirror:") === 0) args.push("mirror", action.substring(7))
    else args.push(action)
    Quickshell.execDetached(args)
    layoutSettleTimer.restart()
  }

  // Hyprland needs a moment to reconfigure outputs before the readback is current.
  Timer {
    id: layoutSettleTimer
    interval: 800
    onTriggered: root.refreshMonitors()
  }

  function setMonitorScale(name, scale) {
    Quickshell.execDetached([Paths.shellScripts + "/set-monitor-scale.sh", name, String(scale)])
    refreshMonitors()
  }

  // Fire-and-forget Process instances, one per get, created on demand so
  // concurrent per-monitor refreshes (there can be several outputs) don't
  // share/overwrite a single Process's state mid-flight.
  Component {
    id: brightnessGetComponent
    Process {
      id: proc
      property string monitorName: ""
      command: [Paths.shellScripts + "/monitor-brightness.sh", "get", monitorName]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          var pct = parseInt(String(text || "").trim(), 10)
          if (!isNaN(pct)) {
            var copy = Object.assign({}, root.brightnessByMonitor)
            copy[proc.monitorName] = pct
            root.brightnessByMonitor = copy
            if (!root.brightnessSeeded) {
              root.brightnessPct = pct
              root.brightnessSeeded = true
            }
          }
          proc.destroy()
        }
      }
    }
  }

  Process {
    id: monitorsProc
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.monitors = JSON.parse(text || "[]")
        } catch (e) {
          return
        }
        // Seed the slider from the hardware exactly once, so it opens showing
        // the real brightness. Every later read is panel-driven — see below.
        if (!root.brightnessSeeded) root.refreshAllBrightness()
      }
    }
  }

  // Monitors only, and only while the panel is up.
  //
  // This used to poll every 5s forever AND call refreshAllBrightness() on
  // every reply, which meant a `ddcutil getvcp` per external monitor every
  // five seconds for the whole session — a DDC/CI round trip is ~0.4s of i2c
  // traffic each (see scripts/monitor-brightness.sh), so the shell was
  // permanently talking to the monitors to refresh a number nobody was
  // looking at. Hover already calls refreshMonitors(), and the panel reads
  // brightness when it becomes visible; this only keeps the list current
  // while it stays open.
  Timer {
    interval: 5000
    running: panel.visible
    repeat: true
    onTriggered: root.refreshMonitors()
  }

  Component.onCompleted: {
    root.refreshMonitors()
    fontListProc.running = true
    root.refreshFontSize()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍹"
    onEntered: root.bar.hoverOpen(root.moduleName)
    onExited: root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    // Shared HoverPanel geometry, like every other panel. This used to
    // re-specify `anchors`/`margins` itself with `top: root.barSize + 4`,
    // which is exactly the double-count HoverPanel's own margins comment
    // warns about: the bar already reserves its height through
    // exclusiveZone, so adding barSize again dropped this one panel ~30px
    // below all the others and opened a dead gap the pointer had to cross
    // before hoverCloseTimer gave up.
    anchorWidget: root
    implicitWidth: Style.panelWidth.normal + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

    // Talking to a monitor over DDC/CI is slow, so read the hardware only
    // when this panel is actually on screen — see refreshAllBrightness().
    onOpened: {
      root.refreshMonitors()
      root.refreshAllBrightness()
      root.refreshFontSize()
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.lg

      PanelSectionHeader { text: "BRIGHTNESS" }

      Column {
        width: parent.width
        spacing: Style.spacing.xs

        // A value beside its label — Style.emphasis.dim, matching every
        // other "current reading" caption in the shell (e.g. Weather's
        // current-conditions subtitle) instead of a one-off opacity.
        Text {
          text: Math.round(root.brightnessPct) + "%"
            + (root.activeMonitors.length > 1 ? "  ·  " + root.activeMonitors.length + " monitors" : "")
          color: Color.menu.text
          opacity: Style.emphasis.dim
          font.pixelSize: Style.font.bodySmall
          font.family: Style.font.family
        }

        // Single slider for every connected monitor. `onMoved` only paints
        // (PanelSlider's own liveValue keeps the drag instantly responsive);
        // the ddcutil/brightnessctl calls fire once from `onReleased`, not
        // on every drag tick — see the header comment.
        PanelSlider {
          width: parent.width
          bar: root.bar
          minimum: 1
          maximum: 100
          integer: true
          value: root.brightnessPct
          onMoved: function(v) { root.brightnessPct = v }
          onReleased: function(v) { root.applyBrightnessAll(v) }
        }
      }

      PanelSectionHeader { text: "WALLPAPER" }

      PanelRow {
        width: parent.width
        // md-image, same action-row shape as the System and Network tools.
        glyph: "\u{f02e9}"
        label: "Choose wallpaper…"
        onActivated: { root.openWallpaperPicker(); root.bar.closePanel(root.moduleName) }
      }

      PanelSectionHeader { text: "FONT" }

      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        Repeater {
          model: root.fontChoices
          Chip {
            required property string modelData
            text: modelData
            selected: Style.fontFamily === modelData
            onClicked: root.setFont(modelData)
          }
        }
      }

      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        Repeater {
          model: root.fontSizes
          Chip {
            required property int modelData
            text: String(modelData)
            selected: root.currentFontSize === modelData
            onClicked: root.setFontSize(modelData)
          }
        }
      }

      PanelSectionHeader { text: "MONITORS" }

      Repeater {
        model: root.monitors
        Column {
          id: monitorRow
          required property var modelData
          width: content.width
          spacing: Style.spacing.sm

          readonly property bool disabled: !!modelData.disabled
          readonly property string mirrorOf: modelData.mirrorOf && modelData.mirrorOf !== "none" ? modelData.mirrorOf : ""
          readonly property string layoutValue: disabled ? "off" : (mirrorOf ? "mirror:" + mirrorOf : "extend")

          Row {
            spacing: Style.spacing.md
            Text {
              text: monitorRow.modelData.name
              color: Color.menu.text
              font.pixelSize: Style.font.bodySmall
              font.family: Style.font.family
            }
            Text {
              text: monitorRow.disabled ? "off"
                : monitorRow.modelData.width + "x" + monitorRow.modelData.height + "@" + Math.round(monitorRow.modelData.refreshRate) + "Hz"
                  + (monitorRow.mirrorOf ? "  ·  mirroring " + monitorRow.mirrorOf : "")
              color: Color.menu.text
              opacity: Style.emphasis.dim
              font.pixelSize: Style.font.bodySmall
              font.family: Style.font.family
            }
          }

          // "Off" is hidden on the last active output so the session keeps a screen.
          Flow {
            visible: root.monitors.length > 1
            width: parent.width
            spacing: Style.spacing.sm
            Repeater {
              model: {
                var opts = [{ value: "extend", label: "Extend" }]
                var others = 0
                for (var i = 0; i < root.monitors.length; i++) {
                  var m = root.monitors[i]
                  if (m.name === monitorRow.modelData.name || m.disabled) continue
                  if (m.mirrorOf && m.mirrorOf !== "none") continue
                  others++
                  opts.push({ value: "mirror:" + m.name, label: "Mirror " + m.name })
                }
                if (others > 0 || monitorRow.disabled) opts.push({ value: "off", label: "Off" })
                return opts
              }
              Chip {
                required property var modelData
                text: modelData.label
                selected: modelData.value === monitorRow.layoutValue
                onClicked: if (!selected) root.setMonitorLayout(monitorRow.modelData.name, modelData.value)
              }
            }
          }

          Flow {
            visible: !monitorRow.disabled
            width: parent.width
            spacing: Style.spacing.sm
            Repeater {
              model: [1, 1.25, 1.5, 1.666667, 2]
              Chip {
                required property real modelData
                // Hyprland reports 1.666667 back as 1.6666666, so compare with a tolerance.
                selected: Math.abs(Number(monitorRow.modelData.scale) - modelData) < 0.01
                text: (Math.round(modelData * 100) / 100) + "x"
                onClicked: root.setMonitorScale(monitorRow.modelData.name, modelData)
              }
            }
          }
        }
      }
    }
  }
}
