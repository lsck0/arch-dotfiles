import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell (its weather panel needs its own
// location/API-key config). Rebuilt 2026-09-02 from a single wttr.in call
// plus a tooltip into the SPEC's three tiers: current conditions, a rolling
// 24h hourly series, and a 3-day forecast.
//
// PRIVACY: the SPEC says "use the current location but NOT REVEAL IT". This
// file never receives a coordinate, a place name, a timezone or a
// sunrise/sunset time — weather-fetch.sh whitelists the fields before the
// JSON gets here, so no edit to this file can leak a location it was never
// given. `source` says *how* the location was determined, never where.
//
// All glyphs below were looked up BY NAME in the 0xProto Nerd Font cmap
// rather than guessed. Guessing costs real bugs here: U+F0554 is
// md-vector_arrange_above and U+F0500 is md-teamviewer, both of which were
// plausible-looking guesses for weather/gauge icons in this exact pass.
BarWidget {
  id: root
  moduleName: "weather"

  // NOT `data`. `data` is Item's DEFAULT property — the list its child
  // objects are assigned into — so declaring `property var data` here
  // shadowed it and the Rectangle/Row/MouseArea were never added as visual
  // children. The symptom was baffling: the hover panel worked perfectly
  // (a PanelWindow is its own window, so it survived) while the bar trigger
  // rendered nothing at all and still occupied layout space.
  property var report: null
  property bool ready: false
  property string errorText: ""

  readonly property var current: report && report.current ? report.current : null
  readonly property var hourly: report && report.hourly ? report.hourly : []
  readonly property var daily: report && report.daily ? report.daily : []
  // The API includes today for current conditions; the forecast list starts
  // tomorrow so the panel does not repeat the current day.
  readonly property var forecast: daily.length > 1 ? daily.slice(1) : []
  readonly property string units: report && report.units ? report.units.temp : "°C"
  readonly property string windUnits: report && report.units ? report.units.wind : "km/h"

  // WMO code -> glyph. The old map keyed off wttr.in's free-text condition
  // strings; Open-Meteo returns the WMO enum instead, so this is the same
  // verified glyph set re-keyed rather than a new one.
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

  // Meteorological convention: wind_direction_10m is the direction the wind
  // comes FROM, which is what this compass label reports.
  function compass(deg) {
    var pts = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    return pts[Math.round(Number(deg) / 45) % 8]
  }

  function t(v) { return (Math.round(Number(v) * 10) / 10) + "°" }
  function n0(v) { return Math.round(Number(v)) }

  visible: ready
  implicitWidth: trigger.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  // ---- alerts ------------------------------------------------------------
  //
  // A separate process from the forecast, not another field on it: MeteoAlarm
  // is a different provider with a different failure mode, and a rate-limited
  // or down warnings feed must not take the temperature with it.
  property var alerts: []
  property int countryOthers: 0
  property bool alertsSupported: true

  // Level 3 (orange) is where a warning stops being background information.
  // The bar trigger only changes at all at that point; yellow lives in the
  // panel, where it is read on purpose rather than glanced at.
  readonly property var topAlert: alerts.length > 0 ? alerts[0] : null
  readonly property bool alertProminent: topAlert !== null && Number(topAlert.level) >= 3

  // MeteoAlarm publishes its own awareness palette, and those colours are the
  // whole point of the scale — an "amber warning" that renders in the
  // wallpaper's accent is no longer an amber warning. These four are the
  // exception to the never-hardcode-a-colour rule, for the same reason a
  // traffic light is not themeable.
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

  // Relative minutes, as the script emits them — never a wall-clock time, so
  // a screenshot of the panel cannot narrow the timezone.
  function inWords(minutes) {
    if (minutes === null || minutes === undefined) return ""
    var m = Math.abs(Number(minutes))
    var text = m < 60 ? m + "m" : (m < 1440 ? Math.round(m / 60) + "h" : Math.round(m / 1440) + "d")
    return Number(minutes) < 0 ? text + " ago" : "in " + text
  }

  // ---- radar -------------------------------------------------------------

  // ---- wind / pressure field over the radar square ------------------------
  //
  // A coarse grid from weather-field.sh, already reduced to (u, v) fractions of
  // the radar image so this file never sees a coordinate. Drawn as arrows plus
  // isobars on top of the precipitation.
  property var fieldCells: []
  property real fieldPressureMin: 0
  property real fieldPressureMax: 0
  property string fieldWindUnits: "km/h"
  property string fieldPressureUnits: "hPa"
  readonly property bool hasField: fieldCells.length > 0

  property var radarFrames: []
  property int radarSpanKm: 0

  // Half the image edge, i.e. the distance from the centre marker to the edge
  // of the square. Every range ring is measured against this.
  readonly property real radarReachKm: radarSpanKm > 0 ? radarSpanKm / 2 : 0

  // Ring spacing, snapped to a round number a person can hold in their head.
  // A computed "65.2 km" ring is arithmetically honest and useless to read;
  // three rings at 50/100/150 answers "how far away is that rain" instantly.
  readonly property int radarRingStepKm: {
    if (radarReachKm <= 0) return 0
    var target = radarReachKm / 3
    var nice = [5, 10, 20, 25, 50, 100, 200, 250, 500, 1000]
    // Largest round step that still fits three rings, NOT the smallest step
    // at or above the target: rounding up gave a single 100 km ring inside a
    // 195 km reach, which is a scale mark rather than a scale.
    var chosen = nice[0]
    for (var i = 0; i < nice.length; i++)
      if (nice[i] <= target) chosen = nice[i]
    return chosen
  }

  // Only rings that fit inside the square. The outermost is allowed to reach
  // the edge midpoint but not beyond it, where it would be clipped into four
  // arcs and read as decoration rather than as a scale.
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
  //
  // This was panel-only, on the reasoning that a dozen PNG downloads should not
  // happen unless somebody looks. The cost of that was the whole point of the
  // panel: opening it started a cold fetch and you watched "Loading radar…"
  // for several seconds every time the nine-minute cache had lapsed, which is
  // most times.
  //
  // The timer below keeps the cache warm so the panel is instant, and the
  // script serves the existing loop untouched whenever the manifest is still
  // fresh — so this costs one round of downloads per ten minutes, matching how
  // often RainViewer's own index actually advances. Fetching more often
  // re-downloads identical PNGs; less often and it is stale when you look.
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
            // Keep showing the last good reading rather than blanking the
            // bar on one failed poll.
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

  // Radar and the wind/pressure field, kept warm. Ten minutes because that is
  // the cadence of the upstream index; `triggeredOnStart` so the first open
  // after a shell restart is warm too, rather than the one time it is
  // guaranteed to be cold.
  Timer {
    interval: 10 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshRadar()
  }

  // Not a BarIconButton: that renders a single glyph and hard-sets
  // labelVisible: false, and its `label` is the id of the Text showing
  // `text`, not a settable second string — so asking it for "icon plus
  // temperature" would have drawn the glyph twice. Same Row idiom as
  // Media.qml instead.
  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: hoverArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  Row {
    id: trigger
    anchors.centerIn: parent
    // Matched to System.qml's Stat, so a glyph sits the same distance from its
    // value everywhere on the bar.
    spacing: Style.spacing.sm

    // Orange-or-worse warnings only, and in MeteoAlarm's own colour. A bar
    // that turns accent-coloured for every yellow "it might be breezy" stops
    // meaning anything; this is the glyph you are supposed to look twice at.
    // md-alert U+F0026, verified by name against the 0xProto cmap.
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.alertProminent
      textFormat: Text.PlainText
      text: "\u{f0026}"
      color: root.topAlert ? root.alertColor(root.topAlert.level) : Color.urgent
      font.family: root.bar ? root.bar.iconFontFamily : Style.font.iconFamily
      font.pixelSize: Style.font.icon

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
    // Wider than the other panels on purpose: three tiers of data do not fit
    // at the usual 340-380, and the hourly series in particular needs
    // horizontal room. Tabs were rejected — they need a click, which fights
    // the hover model.
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

    // Advance the radar loop. Only while the panel is visible and only when
    // there is more than one frame — a single-frame "loop" is a still image
    // and a timer repainting it is pure waste.
    Timer {
      interval: 250
      repeat: true
      running: panel.visible && root.radarPlaying && root.radarFrames.length > 1
      onTriggered: root.radarIndex = (root.radarIndex + 1) % root.radarFrames.length
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

      // --- alerts ---
      //
      // Above the current conditions, because a warning is the one thing here
      // that is worth interrupting for. Absent entirely when there is nothing
      // to say, rather than an "all clear" row that costs space every day to
      // be useful twice a year.
      Column {
        width: parent.width
        spacing: Style.spacing.xs
        visible: root.alerts.length > 0 || !root.alertsSupported

        // WHY THE WARNINGS SECTION IS EMPTY, when it is empty for a reason the
        // user can do nothing about. MeteoAlarm covers ~38 European countries
        // and nothing outside that footprint; weather-alerts.sh reports the
        // difference between "no warnings" and "no source" deliberately, and
        // this is the half of that contract that was missing — `alertsSupported`
        // was assigned from the script's `supported` flag and then read by
        // nobody, so an unsupported region looked identical to a calm day.
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
            // A left rule in the awareness colour, so the severity is
            // readable at a glance without tinting the whole card so hard it
            // fights the text on top of it.
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
                  // `event` is a controlled phrase from the issuing service,
                  // never free prose — see weather-alerts.sh on why no
                  // headline or description crosses into this file.
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
                  // "here" came from a polygon test, "region" only from a
                  // county-name match — say which, rather than implying the
                  // looser one is as certain as the tighter one.
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

      // --- current ---
      Row {
        width: parent.width
        spacing: Style.spacing.md

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.current ? root.iconFor(root.current.code, root.current.isDay) : "\u{f0590}"
          color: Color.menu.text
          font.family: Style.font.iconFamily
          font.pixelSize: Style.font.displayLarge
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xxs
          Text {
            text: root.current ? root.t(root.current.temp) : "—"
            color: Color.menu.text
            font.family: Style.font.family; font.pixelSize: Style.font.display
          }
          Text {
            text: root.current
              ? root.labelFor(root.current.code) + "  ·  feels " + root.t(root.current.feelsLike)
              : (root.errorText || "…")
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

        // Wind gets the arrow treatment: md-navigation points north at
        // rotation 0, so rotating by direction+180 makes it point the way
        // the wind is travelling, while the text names where it comes from.
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
      PanelSectionHeader { text: "NEXT 24 HOURS" }

      // --- hourly sparkline ---
      // A Canvas is the right tool here, unlike the media visualizer's six
      // bars: this is an actual polyline over 24 points, redrawn only when
      // the data changes (twice an hour), not every frame.
      Item {
        width: parent.width
        height: Style.space(84)
        visible: root.hourly.length > 0

        Canvas {
          id: spark
          anchors.fill: parent
          antialiasing: true

          readonly property var pts: root.hourly
          onPtsChanged: requestPaint()
          Component.onCompleted: requestPaint()

          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var n = pts.length
            if (n < 2) return

            var padL = 36, padR = 36, padB = 14, padT = 4
            var w = width, h = height - padB - padT
            var lo = Infinity, hi = -Infinity
            for (var i = 0; i < n; i++) {
              var v = Number(pts[i].temp)
              if (v < lo) lo = v
              if (v > hi) hi = v
            }
            if (hi - lo < 1) { hi = lo + 1 }
            var xs = function (i) { return padL + (i / (n - 1)) * (w - padL - padR) }
            var ys = function (v) { return padT + h - ((v - lo) / (hi - lo)) * h }

            // Axes make the scale and zero point legible even when the
            // temperature line is nearly flat.
            ctx.strokeStyle = Color.menu.text
            ctx.globalAlpha = 0.35
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(padL, padT)
            ctx.lineTo(padL, padT + h)
            ctx.lineTo(w - padR, padT + h)
            ctx.stroke()
            ctx.globalAlpha = 1

            // Vertical temperature scale labels. Keep them outside the plot so
            // the labels cannot overlap the line or rain bars.
            ctx.fillStyle = Color.menu.text
            ctx.globalAlpha = 0.65
            ctx.font = Style.font.caption + 'px "' + Style.font.family + '"'
            ctx.textAlign = "right"
            ctx.fillText(Math.round(hi) + "°", padL - 5, padT + Style.font.caption)
            ctx.fillText(Math.round((hi + lo) / 2) + "°", padL - 5, padT + h / 2 + Style.font.caption / 2)
            ctx.fillText(Math.round(lo) + "°", padL - 5, padT + h)
            ctx.textAlign = "left"
            ctx.globalAlpha = 1

            // Rain-probability axis on the right: its own vertical line (like
            // the left temperature axis has), with labels outside it so they
            // read as belonging to that line rather than floating in the plot.
            ctx.strokeStyle = Color.accent
            ctx.globalAlpha = 0.35
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(w - padR, padT)
            ctx.lineTo(w - padR, padT + h)
            ctx.stroke()
            ctx.globalAlpha = 1

            ctx.fillStyle = Color.accent
            ctx.globalAlpha = 0.7
            ctx.textAlign = "left"
            ctx.fillText("100%", w - padR + 6, padT + h * 0.4 + Style.font.caption / 2)
            ctx.fillText("0%", w - padR + 6, padT + h)
            ctx.globalAlpha = 1

            // Horizontal reference line at zero when it falls in the visible
            // temperature range.
            if (lo <= 0 && hi >= 0) {
              ctx.strokeStyle = Color.menu.text
              ctx.globalAlpha = 0.2
              ctx.beginPath()
              ctx.moveTo(padL, ys(0))
              ctx.lineTo(w - padR, ys(0))
              ctx.stroke()
              ctx.globalAlpha = 1
            }

            // rain bars first, behind the temperature line
            ctx.fillStyle = Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)
            var bw = Math.max(2, (w - 8) / n - 2)
            for (i = 0; i < n; i++) {
              var pop = Math.max(0, Math.min(100, Number(pts[i].pop) || 0))
              if (pop <= 0) continue
              // Capped at 60% of the chart, not 100%. In a place where
              // every hour is 100% rain (this was written against Glasgow)
              // full-height bars swallow the temperature line entirely.
              var bh = (pop / 100) * h * 0.6
              ctx.fillRect(xs(i) - bw / 2, padT + h - bh, bw, bh)
            }

            // temperature line
            ctx.strokeStyle = Color.menu.text
            ctx.lineWidth = 1.5
            ctx.beginPath()
            for (i = 0; i < n; i++) {
              var x = xs(i), y = ys(Number(pts[i].temp))
              if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
            }
            ctx.stroke()

            // hour labels every 6h, plus min/max temp markers
            ctx.fillStyle = Color.menu.text
            ctx.globalAlpha = 0.5
            // Quoted: Canvas's CSS-ish font parser drops a family name
            // containing spaces ("Context2D: The font families specified
            // are invalid: 0xProtoNerdFont") and silently falls back.
            ctx.font = Style.font.caption + 'px "' + Style.font.family + '"'
            for (i = 0; i < n; i += 6) {
              ctx.fillText(pts[i].h, xs(i) - 6, height - 3)
            }
            ctx.globalAlpha = 1
          }
        }

        // Redraw when the palette changes, or the sparkline keeps the old
        // wallpaper's colors until the next fetch. Both roots it draws with
        // are watched: the rain bars and right-hand axis are `accent`, but
        // the temperature line, the left axis and every label are
        // `Color.menu.text`, which is `foreground` — watching only accent
        // left half the chart on the previous wallpaper's palette.
        Connections {
          target: Color
          function onAccentChanged() { spark.requestPaint() }
          function onForegroundChanged() { spark.requestPaint() }
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
          text: "bars = chance of rain"
          color: Color.menu.text; opacity: Style.emphasis.faint
          font.family: Style.font.family; font.pixelSize: Style.font.caption
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "3-DAY FORECAST" }

      // --- 3-day ---
      Column {
        width: parent.width
        spacing: Style.spacing.xs

        Repeater {
          model: root.forecast
          delegate: Row {
            required property var modelData
            width: content.width
            spacing: Style.spacing.sm

            Text {
              width: Style.space(74)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              color: Color.menu.text
              font.family: Style.font.family; font.pixelSize: Style.font.caption
            }
            Text {
              width: Style.space(20)
              anchors.verticalCenter: parent.verticalCenter
              // "windy" is derived, not a WMO code — the enum has no windy
              // value, so a strong-breeze day overrides the sky glyph.
              text: modelData.windy ? "\u{f059d}" : root.iconFor(modelData.code, 1)
              color: Color.menu.text
              font.family: Style.font.iconFamily; font.pixelSize: Style.font.body
            }
            Text {
              width: Style.space(96)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.windy ? "Windy" : root.labelFor(modelData.code)
              color: Color.menu.text; opacity: Style.emphasis.dim
              font.family: Style.font.family; font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Text {
              width: Style.space(64)
              anchors.verticalCenter: parent.verticalCenter
              text: "\u{f0597} " + root.n0(modelData.pop) + "%"
              color: Color.menu.text; opacity: Style.emphasis.dim
              // Glyph + digits in one Text: the whole thing takes the icon
              // family. Digits render fine in a Nerd Font, and splitting a
              // two-token string is more churn than it is worth. Strings
              // carrying *user* text get split instead — see Clock.qml.
              font.family: Style.font.iconFamily; font.pixelSize: Style.font.caption
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.t(modelData.hi) + "  " + root.t(modelData.lo)
              color: Color.menu.text
              font.family: Style.font.family; font.pixelSize: Style.font.caption
            }
          }
        }
      }

      PanelSeparator {}
      PanelSectionHeader {
        text: "RADAR" + (root.radarSpanKm > 0 ? "  ·  " + root.radarSpanKm + " km across" : "")
      }

      // --- radar loop ---
      //
      // Precipitation only, over a flat surface, with a centre marker. There
      // is deliberately no street map underneath: compositing the radar over
      // one would draw the user's own town in the panel, and a screenshot
      // would then give away the location the rest of this widget goes to
      // some length never to state. Distance is conveyed by the span label
      // and the range ring instead.
      Item {
        id: radarBox
        width: parent.width
        // A BAND ACROSS THE PANEL, not a framed square floating in one.
        //
        // The radar used to be a 240px box, centred, with its own background
        // fill, border and corner radius — a card inside a card, narrower than
        // every other row, which is exactly why it read as glued on. The
        // hourly sparkline above it is a bare Canvas spanning the full content
        // width with no chrome at all, and that is what makes it feel like
        // part of the panel rather than a guest in it. Same treatment here.
        //
        // The frames are transparent PNG overlays, so with no fill behind them
        // the precipitation sits directly on the panel background and the crop
        // edges are invisible.
        height: Math.round(width * 0.62)
        visible: root.radarFrames.length > 0
        clip: true

        // The source is square; the band is wider than tall, so the square is
        // scaled to the band's WIDTH and cropped equally top and bottom.
        // Everything drawn on top maps through these two numbers.
        readonly property real imgSize: width
        readonly property real yOffset: (height - imgSize) / 2

        // One Image, re-sourced per frame, rather than a stack of twelve.
        // `cache: true` keeps the decoded frames warm so the loop does not
        // re-read them from disk every pass.
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

        // --- range rings, wind vectors, isobars and a compass ---
        //
        // One Canvas for the entire overlay: they share a coordinate space and
        // a repaint trigger, and the rings used to be separate QML Items on top
        // of the image, which is one more thing to keep aligned for no gain.
        // Repainted only when the data or the palette changes — the radar loop
        // underneath animates on its own and does not touch this layer.
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

          Connections {
            target: Color
            function onForegroundChanged() { fieldCanvas.requestPaint() }
            function onAccentChanged() { fieldCanvas.requestPaint() }
          }

          // Bilinear sample of the pressure grid, in (u, v) space. Used by the
          // isobar tracer so contours are smooth across cells rather than
          // stepping at every grid line.
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

              // The band shows a square source cropped top and bottom, so
              // everything drawn on top has to use the SQUARE's geometry, not
              // the band's. S is the square edge; oy is where its top sits.
              var S = radarBox.imgSize
              var oy = radarBox.yOffset
              function px(u) { return u * S }
              function py(v) { return oy + v * S }

              // ---- isobars ------------------------------------------------
              //
              // Marching squares over the grid. Only drawn when the field
              // actually varies: over a flat pressure field the contours would
              // be noise chasing the model's rounding.
              var values = []
              var hasPressure = true
              for (var i = 0; i < cells.length; i++) {
                if (cells[i].hpa === undefined) { hasPressure = false; break }
                values.push(Number(cells[i].hpa))
              }

              if (hasPressure && root.fieldPressureMax - root.fieldPressureMin >= 0.8) {
                // 1 hPa is the standard isobar interval on a surface chart at
                // this scale; 4 hPa would give a single line over a 2 hPa
                // spread.
                // EVERY NAME IN THIS FUNCTION IS UNIQUE, and that is a rule
                // rather than a style preference. `var` is function-scoped, so
                // the isobar block and the wind block below share one scope: an
                // earlier version declared `var step` in both (1 hPa here, the
                // arrow lattice pitch there) and `cx`/`cy` both as the marching
                // -squares column/row here and as the centre coordinates near
                // the bottom. It only worked because the blocks happen to run
                // in order, and the `reach`/`reachKm` comment further down
                // records what it cost when that assumption broke — a Canvas
                // that throws mid-paint loses the ENTIRE overlay, not the one
                // shape with the bad value.
                var isobarStep = 1.0
                var firstIsobar = Math.ceil(root.fieldPressureMin / isobarStep) * isobarStep
                ctx.lineWidth = 1
                ctx.strokeStyle = Color.menu.text
                ctx.globalAlpha = 0.42
                // Sub-sampled marching squares: the 5x5 grid is traced on a
                // finer lattice through the bilinear sampler, which is what
                // turns four straight cell-edges into a curve.
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

              // ---- wind vectors -------------------------------------------
              //
              // DRAWN ON A DENSER LATTICE THAN THE DATA, by interpolating the
              // grid rather than fetching more of it. Open-Meteo bills per
              // location, so a 13x13 field of real samples would be 169
              // locations every nine minutes; wind at 100 km spacing is a
              // smooth field, so bilinear interpolation between the 25 real
              // samples is both free and physically reasonable.
              //
              // The components are interpolated, NOT speed and direction.
              // Averaging bearings is wrong at the wrap: halfway between 350°
              // and 10° is 0°, but the mean of the numbers is 180° — an arrow
              // pointing exactly backwards.
              var ux = [], vy = []
              for (var c = 0; c < cells.length; c++) {
                var sp = Number(cells[c].wind) || 0
                // Meteorological `dir` is where the wind comes FROM; store the
                // vector it is going TO, which is what gets drawn.
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

              // Odd so one arrow lands dead centre, under the location marker's
              // own ring rather than beside it.
              var density = 17
              var latticeStep = S / density
              // Sized to the lattice, so raising `density` shrinks the arrows
              // instead of overlapping them. 0.30, not 0.42: at the larger
              // density the arrows were still reading as the subject of the
              // picture rather than as texture over the precipitation, which
              // is what the radar is actually for.
              var arrowReach = latticeStep * 0.28

              ctx.strokeStyle = Color.accent
              ctx.fillStyle = Color.accent
              ctx.lineWidth = 1

              for (var gy = 0; gy < density; gy++) {
                for (var gx = 0; gx < density; gx++) {
                  // Cell centres, so the field is inset from the edges rather
                  // than half-clipped along them.
                  var fu = (gx + 0.5) / density
                  var fv = (gy + 0.5) / density
                  var x = px(fu), y = py(fv)
                  if (y < -arrowReach || y > height + arrowReach) continue

                  var sx = sample(ux, fu * (n - 1), fv * (n - 1))
                  var sy = sample(vy, fu * (n - 1), fv * (n - 1))
                  var speed = Math.sqrt(sx * sx + sy * sy)
                  if (speed < 0.01) continue
                  var dx = sx / speed, dy = sy / speed

                  // Normalised against the field's own range rather than
                  // against zero, so a calm day still shows structure instead
                  // of a uniform mat of minimum-length arrows.
                  var strength = Math.min(1, speed / maxWind)
                  // Curved: sqrt lifts the low end so gentle flow is still
                  // legible, while the top stays distinct.
                  var shaped = Math.sqrt(strength)
                  var len = arrowReach * (0.55 + 0.45 * shaped)
                  // Much fainter overall, and with a wider spread between calm
                  // and strong — the field should be something the eye reads
                  // through, not the brightest thing in the frame.
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

              // ---- range rings, labels and the centre marker ---------------
              //
              // Drawn here rather than as QML Items on top. They share the
              // square's transform with the arrows and the isobars, and having
              // one drawing own the whole overlay is what stops the radar
              // reading as a separate pasted-in widget.
              // `reachKm` and `arrowReach` are separate names because they
              // once were not. The wind block declared `var reach` for the
              // arrow half-length and this block declared `var reach` for the
              // radar's ground reach in km; `var` is function-scoped, so the
              // two were one variable. Any path that left it holding the
              // arrow-length value produced a nonsense ring radius — and a
              // Canvas that throws mid-paint loses the ENTIRE overlay, not just
              // the ring, which is how one bad radius blanked the rings, the
              // arrows, the isobars and the compass at once. Every declaration
              // in this function now has a name of its own; see the note in the
              // isobar block.
              var centreX = px(0.5), centreY = py(0.5)
              var reachKm = Number(root.radarReachKm) || 0
              var rings = root.radarRingsKm
              ctx.textAlign = "center"
              ctx.font = Style.font.caption + 'px "' + Style.font.family + '"'
              for (var r = 0; r < rings.length; r++) {
                var km = rings[r]
                var rad = S / 2 * (Number(km) / Math.max(1, reachKm))
                // Belt and braces after the above: a non-finite or negative
                // radius is the one argument ctx.arc refuses outright.
                if (!isFinite(rad) || rad <= 0) continue
                ctx.strokeStyle = Color.menu.text
                ctx.globalAlpha = r === 0 ? 0.26 : 0.15
                ctx.lineWidth = 1
                ctx.beginPath()
                ctx.arc(centreX, centreY, rad, 0, Math.PI * 2)
                ctx.stroke()

                // Label sat on the ring, above the centre. A pill behind it
                // would be another box; a short gap in the ring reads cleaner.
                var label = km + " km"
                var lw = ctx.measureText(label).width
                ctx.globalAlpha = 1
                ctx.fillStyle = Color.menu.background
                // Tall enough to swallow the ring stroke completely — a
                // slightly short box left a sliver of the arc peeking out
                // above the label, which reads as a rendering seam.
                ctx.fillRect(centreX - lw / 2 - 4, centreY - rad - Style.font.caption * 0.80,
                             lw + 8, Style.font.caption * 1.30)
                ctx.fillStyle = Color.menu.text
                ctx.globalAlpha = 0.5
                ctx.fillText(label, centreX, centreY - rad + Style.font.caption * 0.28)
              }
              ctx.globalAlpha = 1

              // You are here — the one location fact this panel states, and it
              // is relative to an unlabelled square, so it says nothing.
              // Small, and ringed in the panel background. It was a plain 9px
              // disc, which was fine over five big arrows and far too heavy
              // once the field became a few hundred small ones — it read as a
              // blob sitting on the map rather than a position on it. The ring
              // is what keeps a 3px dot findable among arrows of its own colour.
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

              // ---- compass ------------------------------------------------
              //
              // Bottom-left, away from the centre marker and the range labels.
              // Without it the arrows are a direction relative to nothing.
              //
              // Was a bare circle with a crosshair through it: crude on its
              // own, and with a hundred arrows now crossing the same pixels it
              // had no ground of its own to sit on. Redrawn as a rose — a
              // backing disc so the field passes behind it, a thin ring, four
              // ticks with north the long one, and a filled north needle.
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

              // Ticks, not a crosshair: a cross through the middle fights the
              // needle for the same space and reads as a gunsight.
              ctx.globalAlpha = 0.4
              for (var q = 0; q < 4; q++) {
                var qa = q * Math.PI / 2
                var inner = rr - (q === 0 ? rr * 0.45 : rr * 0.2)
                ctx.beginPath()
                ctx.moveTo(cxc + Math.sin(qa) * inner, cyc - Math.cos(qa) * inner)
                ctx.lineTo(cxc + Math.sin(qa) * rr, cyc - Math.cos(qa) * rr)
                ctx.stroke()
              }

              // North needle in the accent, so it reads as the one oriented
              // thing on the dial rather than more chrome.
              ctx.globalAlpha = 0.9
              ctx.fillStyle = Color.accent
              ctx.beginPath()
              ctx.moveTo(cxc, cyc - rr * 0.6)
              ctx.lineTo(cxc - rr * 0.19, cyc + rr * 0.15)
              ctx.lineTo(cxc + rr * 0.19, cyc + rr * 0.15)
              ctx.closePath()
              ctx.fill()

              // Quoted family: Canvas's CSS-ish font parser drops a family name
              // containing spaces and silently falls back.
              ctx.font = Style.font.caption + 'px "' + Style.font.family + '"'
              ctx.textAlign = "center"
              ctx.fillStyle = Color.menu.text
              ctx.globalAlpha = 0.6
              ctx.fillText("N", cxc, cyc - rr - Style.space(4))
              ctx.globalAlpha = 1
            }
        }
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

        // Scrub the loop by hand. Pausing on drag is the point: the reason to
        // touch this at all is to hold one frame still.
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

      // "Unavailable" only once the fetch has actually finished and come back
      // with nothing. A cold cache is twelve PNG downloads, and calling that
      // unavailable while it is in flight is simply wrong — it is the state a
      // first open lands in every time.
      Text {
        width: parent.width
        visible: root.radarFrames.length === 0
        text: radarProc.running ? "Loading radar…" : "Radar unavailable"
        color: Color.menu.text
        opacity: Style.emphasis.disabled
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      // What the overlay is showing, since arrows and thin lines over rain are
      // not self-explanatory.
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
