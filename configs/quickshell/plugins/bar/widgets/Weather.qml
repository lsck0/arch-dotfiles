import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell (its weather panel needs its own location/API-key config).
BarWidget {
  id: root
  moduleName: "weather"

  // NOT `data`.
  property var report: null
  property bool ready: false
  property string errorText: ""

  readonly property var current: report && report.current ? report.current : null
  readonly property var hourly: report && report.hourly ? report.hourly : []
  readonly property var daily: report && report.daily ? report.daily : []
  // The API includes today for current conditions; the forecast list starts tomorrow so the panel does not repeat the current day.
  readonly property var forecast: daily.length > 1 ? daily.slice(1) : []
  readonly property string units: report && report.units ? report.units.temp : "°C"
  readonly property string windUnits: report && report.units ? report.units.wind : "km/h"

  // WMO code -> glyph.
  function iconFor(code, isDay) {
    var c = Number(code)
    var day = isDay === undefined ? 1 : Number(isDay)
    if (c === 0) return day ? "\u{f0599}" : "\u{f0594}"          // sunny / night
    if (c === 1 || c === 2) return day ? "\u{f0595}" : "\u{f0f31}" // partly cloudy
    if (c === 3) return "\u{f0590}"                               // overcast
    if (c === 45 || c === 48) return "\u{f0591}"                  // fog
    if (c >= 51 && c <= 57) return "\u{f0597}"                    // drizzle
    if (c >= 61 && c <= 65) return "\u{f0596}"                    // rain
    if (c === 66 || c === 67) return "\u{f067f}"                  // freezing rain
    if (c >= 71 && c <= 77) return "\u{f0598}"                    // snow
    if (c >= 80 && c <= 82) return "\u{f0596}"                    // rain showers
    if (c === 85 || c === 86) return "\u{f0598}"                  // snow showers
    if (c === 95) return "\u{f067e}"                              // thunderstorm
    if (c === 96 || c === 99) return "\u{f0592}"                  // thunder + hail
    return "\u{f0590}"
  }

  function labelFor(code) {
    var c = Number(code)
    if (c === 0) return "Clear"
    if (c === 1) return "Mainly clear"
    if (c === 2) return "Partly cloudy"
    if (c === 3) return "Overcast"
    if (c === 45 || c === 48) return "Fog"
    if (c >= 51 && c <= 57) return "Drizzle"
    if (c >= 61 && c <= 65) return "Rain"
    if (c === 66 || c === 67) return "Freezing rain"
    if (c >= 71 && c <= 77) return "Snow"
    if (c >= 80 && c <= 82) return "Showers"
    if (c === 85 || c === 86) return "Snow showers"
    if (c === 95) return "Thunderstorm"
    if (c === 96 || c === 99) return "Thunderstorm, hail"
    return "—"
  }

  // Meteorological convention: wind_direction_10m is the direction the wind comes FROM, which is what this compass label reports.
  function compass(deg) {
    var pts = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    return pts[Math.round(Number(deg) / 45) % 8]
  }

  function t(v) { return (Math.round(Number(v) * 10) / 10) + "°" }
  function n0(v) { return Math.round(Number(v)) }

  visible: ready
  implicitWidth: trigger.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  // ---- alerts ------------------------------------------------------------ A separate process from the forecast, not another field on it: MeteoAlarm is a different provider with a different failure mode, and a rate-limited or down warnings feed must not take the temperature with it.
  property var alerts: []
  property int countryOthers: 0
  property bool alertsSupported: true

  // Level 3 (orange) is where a warning stops being background information.
  readonly property var topAlert: alerts.length > 0 ? alerts[0] : null
  readonly property bool alertProminent: topAlert !== null && Number(topAlert.level) >= 3

  // MeteoAlarm publishes its own awareness palette, and those colours are the whole point of the scale — an "amber warning" that renders in the wallpaper's accent is no longer an amber warning.
  function alertColor(level) {
    switch (Number(level)) {
    case 4: return Color.semantic.alertRed
    case 3: return Color.semantic.alertOrange
    case 2: return Color.semantic.warn
    default: return Color.menu.text
    }
  }

  function alertLabel(level) {
    switch (Number(level)) {
    case 4: return "RED"
    case 3: return "ORANGE"
    case 2: return "YELLOW"
    default: return "MINOR"
    }
  }

  // Relative minutes, as the script emits them — never a wall-clock time, so a screenshot of the panel cannot narrow the timezone.
  function inWords(minutes) {
    if (minutes === null || minutes === undefined) return ""
    var m = Math.abs(Number(minutes))
    var text = m < 60 ? m + "m" : (m < 1440 ? Math.round(m / 60) + "h" : Math.round(m / 1440) + "d")
    return Number(minutes) < 0 ? text + " ago" : "in " + text
  }

  // ---- radar -------------------------------------------------------------

  // ---- wind / pressure field over the radar square ------------------------ A coarse grid from weather-field.sh, already reduced to (u, v) fractions of the radar image so this file never sees a coordinate.
  property var fieldCells: []
  property real fieldPressureMin: 0
  property real fieldPressureMax: 0
  property string fieldWindUnits: "km/h"
  property string fieldPressureUnits: "hPa"
  readonly property bool hasField: fieldCells.length > 0

  property var radarFrames: []
  property int radarSpanKm: 0

  // Half the image edge, i.e. the distance from the centre marker to the edge of the square. Every range ring is measured against this.
  readonly property real radarReachKm: radarSpanKm > 0 ? radarSpanKm / 2 : 0

  // Ring spacing, snapped to a round number a person can hold in their head.
  readonly property int radarRingStepKm: {
    if (radarReachKm <= 0) return 0
    var target = radarReachKm / 3
    var nice = [5, 10, 20, 25, 50, 100, 200, 250, 500, 1000]
    // Largest round step that still fits three rings, NOT the smallest step at or above the target: rounding up gave a single 100 km ring inside a 195 km reach, which is a scale mark rather than a scale.
    var chosen = nice[0]
    for (var i = 0; i < nice.length; i++)
      if (nice[i] <= target) chosen = nice[i]
    return chosen
  }

  // Only rings that fit inside the square.
  readonly property var radarRingsKm: {
    var out = []
    if (radarRingStepKm <= 0) return out
    for (var km = radarRingStepKm; km <= radarReachKm; km += radarRingStepKm)
      out.push(km)
    return out
  }
  property int radarIndex: 0
  property bool radarPlaying: true
  readonly property var radarFrame: radarFrames.length > 0
    ? radarFrames[Math.min(radarIndex, radarFrames.length - 1)] : null

  function refresh() {
    if (!fetchProc.running) fetchProc.running = true
    if (!alertsProc.running) alertsProc.running = true
  }

  // PREFETCHED IN THE BACKGROUND, not fetched when you open the panel.
  function refreshRadar() {
    if (!radarProc.running) radarProc.running = true
    if (!fieldProc.running) fieldProc.running = true
  }

  Process {
    id: fetchProc
    command: [Paths.barWidget("weather-fetch.sh")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text || "{}")
          if (d.ok) {
            root.report = d
            root.errorText = ""
            root.ready = true
          } else {
            root.errorText = d.error || "unavailable"
            // Keep showing the last good reading rather than blanking the bar on one failed poll.
            if (!root.report) root.ready = false
          }
        } catch (e) {
          root.errorText = "parse failed"
        }
      }
    }
  }

  Process {
    id: alertsProc
    command: [Paths.barWidget("weather-alerts.sh")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text || "{}")
          root.alertsSupported = d.supported !== false
          root.alerts = Array.isArray(d.alerts) ? d.alerts : []
          root.countryOthers = Number(d.countryOthers) || 0
        } catch (e) {
          root.alerts = []
        }
      }
    }
  }

  Process {
    id: radarProc
    command: [Paths.barWidget("weather-radar.sh")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text || "{}")
          if (!d.ok) return
          root.radarFrames = Array.isArray(d.frames) ? d.frames : []
          root.radarSpanKm = Number(d.spanKm) || 0
          root.radarIndex = 0
        } catch (e) {}
      }
    }
  }

  Process {
    id: fieldProc
    command: [Paths.barWidget("weather-field.sh")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text || "{}")
          if (!d.ok) return
          root.fieldCells = Array.isArray(d.cells) ? d.cells : []
          root.fieldPressureMin = Number(d.pressureMin) || 0
          root.fieldPressureMax = Number(d.pressureMax) || 0
          root.fieldWindUnits = String(d.windUnits || "km/h")
          root.fieldPressureUnits = String(d.pressureUnits || "hPa")
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: 30 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Radar and the wind/pressure field, kept warm.
  Timer {
    interval: 10 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshRadar()
  }

  // Not a BarIconButton: that renders a single glyph and hard-sets labelVisible: false, and its `label` is the id of the Text showing `text`, not a settable second string — so asking it for "icon plus temperature" would have drawn the glyph twice.
  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: hoverArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  Row {
    id: trigger
    anchors.centerIn: parent
    // Matched to System.qml's Stat, so a glyph sits the same distance from its value everywhere on the bar.
    spacing: Style.spacing.sm

    // Orange-or-worse warnings only, and in MeteoAlarm's own colour.
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.alertProminent
      textFormat: Text.PlainText
      text: "\u{f0026}"
      color: root.topAlert ? root.alertColor(root.topAlert.level) : Color.urgent
      font.family: root.bar ? root.bar.iconFontFamily : Style.font.iconFamily
      font.pixelSize: Style.font.icon
      // A live warning glows in its own awareness colour, not the accent.
      layer.enabled: Style.fx.glow > 0 && root.alertProminent
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: root.topAlert ? root.alertColor(root.topAlert.level) : Color.urgent
        shadowBlur: 1.0
        shadowVerticalOffset: 0
        shadowHorizontalOffset: 0
        blurMax: Style.fx.glowRadius
        autoPaddingEnabled: true
      }

      SequentialAnimation on opacity {
        running: root.alertProminent
        loops: Animation.Infinite
        NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1.0;  duration: 900; easing.type: Easing.InOutQuad }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.current ? root.iconFor(root.current.code, root.current.isDay) : "\u{f0590}"
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.iconFontFamily : Style.font.iconFamily
      font.pixelSize: Style.font.icon
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      visible: root.current !== null
      text: root.current ? root.t(root.current.temp) : ""
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      opacity: Style.emphasis.strong
    }
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    onEntered: {
      if (root.bar) root.bar.hoverOpen(root.moduleName)
      root.refresh()
      root.refreshRadar()
    }
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    // Wider than the other panels on purpose: three tiers of data do not fit at the usual 340-380, and the hourly series in particular needs horizontal room.
    implicitWidth: Style.panelWidth.wide + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

    onOpened: root.refreshRadar()

    component Stat: Column {
      property string glyph: ""
      property string caption: ""
      property string value: ""
      width: Style.space(96)
      spacing: Style.spacing.xxs
      Row {
        spacing: Style.spacing.xs
        Text {
          text: parent.parent.glyph
          color: Color.menu.text; opacity: Style.emphasis.faint
          font.family: Style.font.iconFamily; font.pixelSize: Style.font.caption
        }
        Text {
          text: parent.parent.caption
          color: Color.menu.text; opacity: Style.emphasis.faint
          font.family: Style.font.family; font.pixelSize: Style.font.caption
        }
      }
      Text {
        text: parent.value
        color: Color.menu.text
        font.family: Style.font.family; font.pixelSize: Style.font.body
      }
    }

    // Advance the radar loop.
    Timer {
      interval: 250
      repeat: true
      running: panel.visible && root.radarPlaying && root.radarFrames.length > 1
      onTriggered: root.radarIndex = (root.radarIndex + 1) % root.radarFrames.length
    }

    // Neon HUD corner brackets around the dropdown.
    HudFrame {}

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

      // --- terminal title bar --- Reads like a TUI window header: tracked accent name plus a blinking block caret.
      Row {
        width: parent.width
        spacing: Style.spacing.sm
        PanelSectionHeader { text: "> WEATHER"; fontSize: Style.font.title }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "_"                                 // blinking block caret
          color: Color.accent
          font.family: Style.font.family; font.pixelSize: Style.font.title
          SequentialAnimation on opacity {
            loops: Animation.Infinite
            NumberAnimation { to: 0.15; duration: 600 }
            NumberAnimation { to: 1.0;  duration: 600 }
          }
        }
      }
      PanelSeparator {}

      // --- alerts --- Above the current conditions, because a warning is the one thing here that is worth interrupting for.
      Column {
        width: parent.width
        spacing: Style.spacing.xs
        visible: root.alerts.length > 0 || !root.alertsSupported

        // WHY THE WARNINGS SECTION IS EMPTY, when it is empty for a reason the user can do nothing about.
        Text {
          width: parent.width
          visible: !root.alertsSupported
          wrapMode: Text.Wrap
          text: "No warning service for this region — MeteoAlarm covers Europe only"
          color: Color.menu.text
          opacity: Style.emphasis.disabled
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.alerts
          delegate: Rectangle {
            required property var modelData
            width: content.width
            height: alertRow.implicitHeight + Style.spacing.sm * 2
            radius: Style.cornerRadius
            color: Util.alpha(root.alertColor(modelData.level), 0.16)
            // A left rule in the awareness colour, so the severity is readable at a glance without tinting the whole card so hard it fights the text on top of it.
            Rectangle {
              width: Style.space(3)
              height: parent.height
              radius: width / 2
              color: root.alertColor(modelData.level)
            }

            Column {
              id: alertRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.spacing.md
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xxs

              Row {
                width: parent.width
                spacing: Style.spacing.sm
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "\u{f0026}"   // md-alert
                  color: root.alertColor(modelData.level)
                  font.family: Style.font.iconFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.alertLabel(modelData.level)
                  color: root.alertColor(modelData.level)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: Style.headerTracking
                  font.bold: true
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  // `event` is a controlled phrase from the issuing service, never free prose — see weather-alerts.sh on why no headline or description crosses into this file.
                  text: modelData.event || modelData.kind || "Weather warning"
                  color: Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: Math.max(0, parent.width - x)
                }
              }

              Text {
                width: parent.width
                text: {
                  var bits = []
                  var starts = root.inWords(modelData.startsIn)
                  var ends = root.inWords(modelData.endsIn)
                  if (Number(modelData.startsIn) > 0 && starts) bits.push("starts " + starts)
                  if (ends) bits.push("ends " + ends)
                  // "here" came from a polygon test, "region" only from a county-name match — say which, rather than implying the looser one is as certain as the tighter one.
                  bits.push(modelData.scope === "here" ? "your area" : "your region")
                  if (modelData.certainty) bits.push(String(modelData.certainty).toLowerCase())
                  return bits.join("  ·  ")
                }
                color: Color.menu.text
                opacity: Style.emphasis.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.countryOthers > 0
          text: root.countryOthers + " more warning" + (root.countryOthers === 1 ? "" : "s")
            + " elsewhere in your country"
          color: Color.menu.text
          opacity: Style.emphasis.disabled
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      PanelSeparator { visible: root.alerts.length > 0 || !root.alertsSupported }

      // --- current --- The hero readout: oversized glowing sky glyph and temperature.
      Row {
        width: parent.width
        spacing: Style.spacing.lg

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.current ? root.iconFor(root.current.code, root.current.isDay) : "\u{f0590}"
          color: Color.accent
          font.family: Style.font.iconFamily
          font.pixelSize: Style.font.displayLarge
          // The live sky condition blooms in the accent.
          layer.enabled: Style.fx.glow > 0
          layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Style.fx.glowColor
            shadowBlur: 1.0
            shadowVerticalOffset: 0
            shadowHorizontalOffset: 0
            blurMax: Style.fx.glowRadius
            autoPaddingEnabled: true
          }
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xxs
          Text {
            text: root.current ? root.t(root.current.temp) : "—"
            color: Color.menu.text
            font.family: Style.font.family; font.pixelSize: Style.font.display
            font.letterSpacing: Style.displayTracking
            // The primary metric glows: a halo behind the numeral, never in the fill.
            layer.enabled: Style.fx.glow > 0
            layer.effect: MultiEffect {
              shadowEnabled: true
              shadowColor: Style.fx.glowColor
              shadowBlur: 1.0
              shadowVerticalOffset: 0
              shadowHorizontalOffset: 0
              blurMax: Style.fx.glowRadius
              autoPaddingEnabled: true
            }
          }
          Text {
            text: root.current
              ? root.labelFor(root.current.code) + "  ·  feels " + root.t(root.current.feelsLike)
              : (root.errorText || "...")
            color: Color.menu.text; opacity: Style.emphasis.dim
            font.family: Style.font.family; font.pixelSize: Style.font.caption
          }
        }
      }

      // --- current detail grid ---
      Grid {
        width: parent.width
        columns: 4
        rowSpacing: Style.spacing.sm
        columnSpacing: Style.spacing.xs
        visible: root.current !== null

        Stat {
          glyph: "\u{f058e}"; caption: "HUMIDITY"      // md-water_percent
          value: root.current ? root.n0(root.current.humidity) + "%" : "—"
        }
        Stat {
          glyph: "\u{f0590}"; caption: "CLOUD"          // md-weather_cloudy
          value: root.current ? root.n0(root.current.cloud) + "%" : "—"
        }
        Stat {
          glyph: "\u{f0599}"; caption: "UV"             // md-weather_sunny
          value: root.current ? (Math.round(Number(root.current.uv) * 10) / 10) : "—"
        }
        Stat {
          glyph: "\u{f029a}"; caption: "PRESSURE"       // md-gauge
          value: root.current ? root.n0(root.current.pressure) + " hPa" : "—"
        }

        // Wind gets the arrow treatment: md-navigation points north at rotation 0, so rotating by direction+180 makes it point the way the wind is travelling, while the text names where it comes from.
        Column {
          width: Style.space(96)
          spacing: Style.spacing.xxs
          Row {
            spacing: Style.spacing.xs
            Text {
              text: "\u{f0390}"                          // md-navigation
              rotation: root.current ? Number(root.current.windDir) + 180 : 0
              color: Color.menu.text; opacity: Style.emphasis.faint
              font.family: Style.font.iconFamily; font.pixelSize: Style.font.caption
            }
            Text {
              text: "WIND"
              color: Color.menu.text; opacity: Style.emphasis.faint
              font.family: Style.font.family; font.pixelSize: Style.font.caption
            }
          }
          Text {
            text: root.current
              ? root.n0(root.current.wind) + " " + root.windUnits + " " + root.compass(root.current.windDir)
              : "—"
            color: Color.menu.text
            font.family: Style.font.family; font.pixelSize: Style.font.body
          }
        }

        Stat {
          glyph: "\u{f059d}"; caption: "GUSTS"          // md-weather_windy
          value: root.current ? root.n0(root.current.gust) + " " + root.windUnits : "—"
        }
        Stat {
          glyph: "\u{f0597}"; caption: "RAIN NOW"       // md-weather_rainy
          value: root.current ? (Math.round(Number(root.current.precip) * 10) / 10) + " mm" : "—"
        }
        Stat {
          glyph: "\u{f050f}"; caption: "FEELS"          // md-thermometer
          value: root.current ? root.t(root.current.feelsLike) : "—"
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "> NEXT 24 HOURS" }

      // --- hourly temperature curve --- The next-24h series as a glowing HUD sparkline, redrawn only when the data changes.
      Sparkline {
        width: parent.width
        height: Style.space(64)
        visible: root.hourly.length > 0
        color: Color.menu.text
        // scale to the temp range (+/-1 padding); defaults 0..1 would push temps off-canvas
        minValue: {
          var m = Infinity
          for (var i = 0; i < root.hourly.length; i++) m = Math.min(m, Number(root.hourly[i].temp))
          return isFinite(m) ? m - 1 : 0
        }
        maxValue: {
          var m = -Infinity
          for (var i = 0; i < root.hourly.length; i++) m = Math.max(m, Number(root.hourly[i].temp))
          return isFinite(m) ? m + 1 : 1
        }
        values: {
          var out = []
          for (var i = 0; i < root.hourly.length; i++) out.push(Number(root.hourly[i].temp))
          return out
        }
      }

      // --- chance-of-rain bars --- One accent bar per forecast hour, height = probability, with 6-hourly tick labels beneath.
      Column {
        width: parent.width
        spacing: Style.spacing.xxs
        visible: root.hourly.length > 0

        Item {
          id: hourlyBars
          width: parent.width
          height: Style.space(28)
          Row {
            anchors.fill: parent
            spacing: 1
            Repeater {
              model: root.hourly
              delegate: Item {
                required property var modelData
                width: (hourlyBars.width - (root.hourly.length - 1)) / Math.max(1, root.hourly.length)
                height: hourlyBars.height
                Rectangle {
                  anchors.bottom: parent.bottom
                  width: parent.width
                  height: Math.max(1, parent.height * Math.max(0, Math.min(100, Number(modelData.pop) || 0)) / 100)
                  color: Util.alpha(Color.accent, 0.55)
                  antialiasing: false
                }
              }
            }
          }
        }

        Row {
          width: parent.width
          spacing: 1
          Repeater {
            model: root.hourly
            delegate: Column {
              required property var modelData
              required property int index
              width: (hourlyBars.width - (root.hourly.length - 1)) / Math.max(1, root.hourly.length)
              spacing: 0
              // condition icon over the hour label, at each 6h tick
              Text {
                text: (index % 6 === 0) ? (modelData.windy ? "\u{f059d}" : root.iconFor(modelData.code, 1)) : ""
                color: Color.accent
                font.family: Style.font.iconFamily; font.pixelSize: Style.font.iconSmall
              }
              Text {
                text: index % 6 === 0 ? modelData.h : ""
                color: Color.menu.text; opacity: Style.emphasis.faint
                font.family: Style.font.family; font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      Row {
        width: parent.width
        visible: root.hourly.length > 0
        Text {
          width: parent.width / 2
          text: {
            if (!root.hourly.length) return ""
            var lo = Infinity, hi = -Infinity
            for (var i = 0; i < root.hourly.length; i++) {
              var v = Number(root.hourly[i].temp)
              if (v < lo) lo = v
              if (v > hi) hi = v
            }
            return "temp " + root.t(lo) + " – " + root.t(hi)
          }
          color: Color.menu.text; opacity: Style.emphasis.faint
          font.family: Style.font.family; font.pixelSize: Style.font.caption
        }
        Text {
          width: parent.width / 2
          horizontalAlignment: Text.AlignRight
          text: "bars > chance of rain"
          color: Color.menu.text; opacity: Style.emphasis.faint
          font.family: Style.font.family; font.pixelSize: Style.font.caption
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "> 3-DAY FORECAST" }

      // --- 3-day --- Compact HUD tiles: tracked day header, sky glyph, hi/lo mono, and a rain gauge.
      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Repeater {
          model: root.forecast
          delegate: Rectangle {
            required property var modelData
            width: (content.width - Style.spacing.sm * (root.forecast.length - 1)) / Math.max(1, root.forecast.length)
            implicitHeight: tile.implicitHeight + Style.spacing.md * 2
            radius: Style.cornerRadius
            color: Style.normalFill

            // HUD corner brackets on each forecast tile.
            HudFrame {}

            Column {
              id: tile
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.leftMargin: Style.spacing.sm
              anchors.rightMargin: Style.spacing.sm
              anchors.topMargin: Style.spacing.md
              spacing: Style.spacing.xs

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: modelData.label
                color: Color.accent
                font.family: Style.font.family; font.pixelSize: Style.font.caption
                font.bold: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Style.headerTracking
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                // "windy" is derived, not a WMO code — the enum has no windy value, so a strong-breeze day overrides the sky glyph.
                text: modelData.windy ? "\u{f059d}" : root.iconFor(modelData.code, 1)
                color: Color.menu.text
                font.family: Style.font.iconFamily; font.pixelSize: Style.font.heading
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: modelData.windy ? "Windy" : root.labelFor(modelData.code)
                color: Color.menu.text; opacity: Style.emphasis.dim
                font.family: Style.font.family; font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.t(modelData.hi) + "  " + root.t(modelData.lo)
                color: Color.menu.text
                font.family: Style.font.family; font.pixelSize: Style.font.caption
              }
              BarGauge {
                width: parent.width
                height: Style.spacing.sm
                segments: 8
                value: Math.max(0, Math.min(100, Number(modelData.pop) || 0)) / 100
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "\u{f0597} " + root.n0(modelData.pop) + "%"
                color: Color.menu.text; opacity: Style.emphasis.dim
                // Glyph + digits in one Text: the whole thing takes the icon family.
                font.family: Style.font.iconFamily; font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      PanelSeparator {}
      PanelSectionHeader {
        text: "> RADAR" + (root.radarSpanKm > 0 ? "  ·  " + root.radarSpanKm + " km across" : "")
      }

      // --- radar loop --- Precipitation only, over a flat surface, with a centre marker.
      Item {
        id: radarBox
        width: parent.width
        // A BAND ACROSS THE PANEL, not a framed square floating in one.
        height: Math.round(width * 0.62)
        visible: root.radarFrames.length > 0
        clip: true

        // The source is square; the band is wider than tall, so the square is scaled to the band's WIDTH and cropped equally top and bottom.
        readonly property real imgSize: width
        readonly property real yOffset: (height - imgSize) / 2

        // One Image, re-sourced per frame, rather than a stack of twelve.
        Image {
          id: radarImage
          x: 0
          y: radarBox.yOffset
          width: radarBox.imgSize
          height: radarBox.imgSize
          source: root.radarFrame ? Util.fileUrl(root.radarFrame.file) : ""
          sourceSize.width: Math.ceil(width * Screen.devicePixelRatio)
          sourceSize.height: Math.ceil(height * Screen.devicePixelRatio)
          fillMode: Image.PreserveAspectFit
          asynchronous: false
          smooth: true
          cache: true
        }

        // A hard accent edge turns the band into a framed scope viewport.
        Rectangle {
          anchors.fill: parent
          color: "transparent"
          radius: Style.cornerRadius
          border.width: Style.normalBorderWidth
          border.color: Util.alpha(Color.accent, Style.hoverBorderAlpha)
        }

        // --- range rings, wind vectors, isobars and a compass --- One Canvas for the entire overlay: they share a coordinate space and a repaint trigger, and the rings used to be separate QML Items on top of the image, which is one more thing to keep aligned for no gain.
        Canvas {
          id: fieldCanvas
          anchors.fill: parent
          antialiasing: true

          readonly property var cells: root.fieldCells
          readonly property var rings: root.radarRingsKm
          onCellsChanged: requestPaint()
          onRingsChanged: requestPaint()
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          Component.onCompleted: requestPaint()

          // HUD brackets frame the radar band like a scope readout.
          HudFrame {}

          Connections {
            target: Color
            function onForegroundChanged() { fieldCanvas.requestPaint() }
            function onAccentChanged() { fieldCanvas.requestPaint() }
          }

          // Bilinear sample of the pressure grid, in (u, v) space.
          function pressureAt(gx, gy, n, values) {
            var x = Math.max(0, Math.min(n - 1.0001, gx))
            var y = Math.max(0, Math.min(n - 1.0001, gy))
            var x0 = Math.floor(x), y0 = Math.floor(y)
            var fx = x - x0, fy = y - y0
            var v00 = values[y0 * n + x0], v10 = values[y0 * n + x0 + 1]
            var v01 = values[(y0 + 1) * n + x0], v11 = values[(y0 + 1) * n + x0 + 1]
            return v00 * (1 - fx) * (1 - fy) + v10 * fx * (1 - fy)
                 + v01 * (1 - fx) * fy + v11 * fx * fy
          }

            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              var cells = root.fieldCells
              if (!cells || cells.length === 0) return

              var n = Math.round(Math.sqrt(cells.length))
              if (n < 2 || n * n !== cells.length) return

              // The band shows a square source cropped top and bottom, so everything drawn on top has to use the SQUARE's geometry, not the band's.
              var S = radarBox.imgSize
              var oy = radarBox.yOffset
              function px(u) { return u * S }
              function py(v) { return oy + v * S }

              // ---- isobars ------------------------------------------------ Marching squares over the grid.
              var values = []
              var hasPressure = true
              for (var i = 0; i < cells.length; i++) {
                if (cells[i].hpa === undefined) { hasPressure = false; break }
                values.push(Number(cells[i].hpa))
              }

              if (hasPressure && root.fieldPressureMax - root.fieldPressureMin >= 0.8) {
                // 1 hPa is the standard isobar interval on a surface chart at this scale; 4 hPa would give a single line over a 2 hPa spread.
                var isobarStep = 1.0
                var firstIsobar = Math.ceil(root.fieldPressureMin / isobarStep) * isobarStep
                ctx.lineWidth = 1
                ctx.strokeStyle = Color.menu.text
                ctx.globalAlpha = 0.42
                // Sub-sampled marching squares: the 5x5 grid is traced on a finer lattice through the bilinear sampler, which is what turns four straight cell-edges into a curve.
                var sub = 6
                var cellsAcross = (n - 1) * sub
                for (var level = firstIsobar; level <= root.fieldPressureMax; level += isobarStep) {
                  ctx.beginPath()
                  for (var msRow = 0; msRow < cellsAcross; msRow++) {
                    for (var msCol = 0; msCol < cellsAcross; msCol++) {
                      var gx0 = msCol / sub, gy0 = msRow / sub
                      var gx1 = (msCol + 1) / sub, gy1 = (msRow + 1) / sub
                      var a = pressureAt(gx0, gy0, n, values)
                      var b = pressureAt(gx1, gy0, n, values)
                      var c = pressureAt(gx1, gy1, n, values)
                      var d = pressureAt(gx0, gy1, n, values)
                      var idx = (a > level ? 8 : 0) | (b > level ? 4 : 0)
                              | (c > level ? 2 : 0) | (d > level ? 1 : 0)
                      if (idx === 0 || idx === 15) continue

                      var px0 = px(gx0 / (n - 1)), px1 = px(gx1 / (n - 1))
                      var py0 = py(gy0 / (n - 1)), py1 = py(gy1 / (n - 1))
                      function lerp(p, q, vp, vq) { return p + (q - p) * ((level - vp) / (vq - vp)) }
                      var top = { x: lerp(px0, px1, a, b), y: py0 }
                      var right = { x: px1, y: lerp(py0, py1, b, c) }
                      var bottom = { x: lerp(px0, px1, d, c), y: py1 }
                      var left = { x: px0, y: lerp(py0, py1, a, d) }

                      function seg(p, q) { ctx.moveTo(p.x, p.y); ctx.lineTo(q.x, q.y) }
                      switch (idx) {
                      case 1: case 14: seg(left, bottom); break
                      case 2: case 13: seg(bottom, right); break
                      case 3: case 12: seg(left, right); break
                      case 4: case 11: seg(top, right); break
                      case 6: case 9:  seg(top, bottom); break
                      case 7: case 8:  seg(left, top); break
                      case 5:  seg(left, top); seg(bottom, right); break
                      case 10: seg(left, bottom); seg(top, right); break
                      }
                    }
                  }
                  ctx.stroke()
                }
                ctx.globalAlpha = 1
              }

              // ---- wind vectors ------------------------------------------- DRAWN ON A DENSER LATTICE THAN THE DATA, by interpolating the grid rather than fetching more of it.
              var ux = [], vy = []
              for (var c = 0; c < cells.length; c++) {
                var sp = Number(cells[c].wind) || 0
                // Meteorological `dir` is where the wind comes FROM; store the vector it is going TO, which is what gets drawn.
                var rr0 = (Number(cells[c].dir) + 180) * Math.PI / 180
                ux.push(Math.sin(rr0) * sp)
                vy.push(-Math.cos(rr0) * sp)
              }

              function sample(field, gx, gy) {
                var x = Math.max(0, Math.min(n - 1.0001, gx))
                var y = Math.max(0, Math.min(n - 1.0001, gy))
                var x0 = Math.floor(x), y0 = Math.floor(y)
                var fx = x - x0, fy = y - y0
                return field[y0 * n + x0] * (1 - fx) * (1 - fy)
                     + field[y0 * n + x0 + 1] * fx * (1 - fy)
                     + field[(y0 + 1) * n + x0] * (1 - fx) * fy
                     + field[(y0 + 1) * n + x0 + 1] * fx * fy
              }

              var maxWind = 1
              for (var w = 0; w < cells.length; w++)
                maxWind = Math.max(maxWind, Number(cells[w].wind) || 0)

              // Odd so one arrow lands dead centre, under the location marker's own ring rather than beside it.
              var density = 17
              var latticeStep = S / density
              // Sized to the lattice, so raising `density` shrinks the arrows instead of overlapping them.
              var arrowReach = latticeStep * 0.28

              ctx.strokeStyle = Color.accent
              ctx.fillStyle = Color.accent
              ctx.lineWidth = 1

              for (var gy = 0; gy < density; gy++) {
                for (var gx = 0; gx < density; gx++) {
                  // Cell centres, so the field is inset from the edges rather than half-clipped along them.
                  var fu = (gx + 0.5) / density
                  var fv = (gy + 0.5) / density
                  var x = px(fu), y = py(fv)
                  if (y < -arrowReach || y > height + arrowReach) continue

                  var sx = sample(ux, fu * (n - 1), fv * (n - 1))
                  var sy = sample(vy, fu * (n - 1), fv * (n - 1))
                  var speed = Math.sqrt(sx * sx + sy * sy)
                  if (speed < 0.01) continue
                  var dx = sx / speed, dy = sy / speed

                  // Normalised against the field's own range rather than against zero, so a calm day still shows structure instead of a uniform mat of minimum-length arrows.
                  var strength = Math.min(1, speed / maxWind)
                  // Curved: sqrt lifts the low end so gentle flow is still legible, while the top stays distinct.
                  var shaped = Math.sqrt(strength)
                  var len = arrowReach * (0.55 + 0.45 * shaped)
                  // Much fainter overall, and with a wider spread between calm and strong — the field should be something the eye reads through, not the brightest thing in the frame.
                  ctx.globalAlpha = 0.13 + 0.29 * shaped

                  var tipX = x + dx * len, tipY = y + dy * len
                  ctx.beginPath()
                  ctx.moveTo(x - dx * len, y - dy * len)
                  ctx.lineTo(tipX, tipY)
                  ctx.stroke()

                  // Arrowhead, back along the shaft from the tip.
                  var head = Math.max(1.5, arrowReach * 0.46)
                  var ang = Math.atan2(dx, -dy)
                  var la = ang + Math.PI * 0.82, ra = ang - Math.PI * 0.82
                  ctx.beginPath()
                  ctx.moveTo(tipX, tipY)
                  ctx.lineTo(tipX + Math.sin(la) * head, tipY - Math.cos(la) * head)
                  ctx.lineTo(tipX + Math.sin(ra) * head, tipY - Math.cos(ra) * head)
                  ctx.closePath()
                  ctx.fill()
                }
              }
              ctx.globalAlpha = 1

              // ---- range rings, labels and the centre marker --------------- Drawn here rather than as QML Items on top.
              var centreX = px(0.5), centreY = py(0.5)
              var reachKm = Number(root.radarReachKm) || 0
              var rings = root.radarRingsKm
              ctx.textAlign = "center"
              ctx.font = Style.font.caption + 'px "' + Style.font.family + '"'
              for (var r = 0; r < rings.length; r++) {
                var km = rings[r]
                var rad = S / 2 * (Number(km) / Math.max(1, reachKm))
                // Belt and braces after the above: a non-finite or negative radius is the one argument ctx.arc refuses outright.
                if (!isFinite(rad) || rad <= 0) continue
                ctx.strokeStyle = Color.menu.text
                ctx.globalAlpha = r === 0 ? 0.26 : 0.15
                ctx.lineWidth = 1
                ctx.beginPath()
                ctx.arc(centreX, centreY, rad, 0, Math.PI * 2)
                ctx.stroke()

                // Label sat on the ring, above the centre.
                var label = km + " km"
                var lw = ctx.measureText(label).width
                ctx.globalAlpha = 1
                ctx.fillStyle = Color.menu.background
                // Tall enough to swallow the ring stroke completely — a slightly short box left a sliver of the arc peeking out above the label, which reads as a rendering seam.
                ctx.fillRect(centreX - lw / 2 - 4, centreY - rad - Style.font.caption * 0.80,
                             lw + 8, Style.font.caption * 1.30)
                ctx.fillStyle = Color.menu.text
                ctx.globalAlpha = 0.5
                ctx.fillText(label, centreX, centreY - rad + Style.font.caption * 0.28)
              }
              ctx.globalAlpha = 1

              // You are here — the one location fact this panel states, and it is relative to an unlabelled square, so it says nothing.
              var markerR = Math.max(2, (Number(S) || 0) * 0.006)
              ctx.beginPath()
              ctx.arc(centreX, centreY, markerR + 1.8, 0, Math.PI * 2)
              ctx.fillStyle = Color.menu.background
              ctx.globalAlpha = 0.9
              ctx.fill()
              ctx.globalAlpha = 1
              ctx.beginPath()
              ctx.arc(centreX, centreY, markerR, 0, Math.PI * 2)
              ctx.fillStyle = Color.accent
              ctx.fill()

              // ---- compass ------------------------------------------------ Bottom-left, away from the centre marker and the range labels.
              var cxc = Math.round(width * 0.115)
              var cyc = Math.round(height * 0.78)
              var rr = Math.max(4, Math.min(width, height) * 0.075)

              ctx.beginPath()
              ctx.arc(cxc, cyc, rr + Style.space(3), 0, Math.PI * 2)
              ctx.fillStyle = Color.menu.background
              ctx.globalAlpha = 0.85
              ctx.fill()

              ctx.strokeStyle = Color.menu.text
              ctx.lineWidth = 1
              ctx.globalAlpha = 0.28
              ctx.beginPath()
              ctx.arc(cxc, cyc, rr, 0, Math.PI * 2)
              ctx.stroke()

              // Ticks, not a crosshair: a cross through the middle fights the needle for the same space and reads as a gunsight.
              ctx.globalAlpha = 0.4
              for (var q = 0; q < 4; q++) {
                var qa = q * Math.PI / 2
                var inner = rr - (q === 0 ? rr * 0.45 : rr * 0.2)
                ctx.beginPath()
                ctx.moveTo(cxc + Math.sin(qa) * inner, cyc - Math.cos(qa) * inner)
                ctx.lineTo(cxc + Math.sin(qa) * rr, cyc - Math.cos(qa) * rr)
                ctx.stroke()
              }

              // North needle in the accent, so it reads as the one oriented thing on the dial rather than more chrome.
              ctx.globalAlpha = 0.9
              ctx.fillStyle = Color.accent
              ctx.beginPath()
              ctx.moveTo(cxc, cyc - rr * 0.6)
              ctx.lineTo(cxc - rr * 0.19, cyc + rr * 0.15)
              ctx.lineTo(cxc + rr * 0.19, cyc + rr * 0.15)
              ctx.closePath()
              ctx.fill()

              // Quoted family: Canvas's CSS-ish font parser drops a family name containing spaces and silently falls back.
              ctx.font = Style.font.caption + 'px "' + Style.font.family + '"'
              ctx.textAlign = "center"
              ctx.fillStyle = Color.menu.text
              ctx.globalAlpha = 0.6
              ctx.fillText("N", cxc, cyc - rr - Style.space(4))
              ctx.globalAlpha = 1
            }
        }

        // CRT scanlines over the scope, on top of everything.
        Scanlines {}
      }


      Row {
        width: parent.width
        visible: root.radarFrames.length > 0
        spacing: Style.spacing.sm

        PanelActionButton {
          iconText: root.radarPlaying ? "\u{f04c}" : "\u{f04b}"   // fa-pause / fa-play
          tooltipText: root.radarPlaying ? "Pause radar" : "Play radar"
          size: Style.space(22)
          fontSize: Style.font.caption
          onClicked: root.radarPlaying = !root.radarPlaying
        }

        // Scrub the loop by hand.
        PanelSlider {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(150)
          bar: root.bar
          minimum: 0
          maximum: Math.max(0, root.radarFrames.length - 1)
          step: 1
          value: root.radarIndex
          onMoved: function (v) {
            root.radarPlaying = false
            root.radarIndex = Math.round(v)
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(92)
          horizontalAlignment: Text.AlignRight
          text: {
            if (!root.radarFrame) return ""
            var m = Number(root.radarFrame.minutes)
            if (root.radarFrame.forecast) return "+" + Math.abs(m) + "m forecast"
            m = Math.abs(m)
            if (m === 0) return "now"
            return (m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m" : m + "m") + " ago"
          }
          color: Color.menu.text
          opacity: root.radarFrame && root.radarFrame.forecast ? 0.85 : 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      // "Unavailable" only once the fetch has actually finished and come back with nothing.
      Text {
        width: parent.width
        visible: root.radarFrames.length === 0
        text: radarProc.running ? "Loading radar..." : "Radar unavailable"
        color: Color.menu.text
        opacity: Style.emphasis.disabled
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      // What the overlay is showing, since arrows and thin lines over rain are not self-explanatory.
      Row {
        width: parent.width
        visible: root.hasField
        Text {
          width: parent.width / 2
          text: "arrows: wind, to " + root.fieldWindUnits
          color: Color.accent
          opacity: Style.emphasis.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Text {
          width: parent.width / 2
          horizontalAlignment: Text.AlignRight
          text: root.fieldPressureMax > 0
            ? "isobars 1 " + root.fieldPressureUnits + "  ·  "
              + root.fieldPressureMin.toFixed(0) + "–" + root.fieldPressureMax.toFixed(0)
            : ""
          color: Color.menu.text
          opacity: Style.emphasis.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
