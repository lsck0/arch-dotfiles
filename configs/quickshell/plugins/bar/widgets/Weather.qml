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
  implicitWidth: trigger.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: barSize

  function refresh() { if (!fetchProc.running) fetchProc.running = true }

  Process {
    id: fetchProc
    command: [Quickshell.env("HOME") + "/projects/arch-dotfiles/configs/quickshell/plugins/bar/widgets/weather-fetch.sh"]
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

  Timer {
    interval: 30 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
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
    spacing: Style.spacing.xs

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
      opacity: 0.85
    }
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    onEntered: { if (root.bar) root.bar.hoverOpen(root.moduleName); root.refresh() }
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
    implicitWidth: Style.space(460) + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

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
          color: Color.menu.text; opacity: 0.5
          font.family: Style.font.iconFamily; font.pixelSize: Style.font.caption
        }
        Text {
          text: parent.parent.caption
          color: Color.menu.text; opacity: 0.5
          font.family: Style.font.family; font.pixelSize: Style.font.caption
        }
      }
      Text {
        text: parent.value
        color: Color.menu.text
        font.family: Style.font.family; font.pixelSize: Style.font.body
      }
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

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
            color: Color.menu.text; opacity: 0.7
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
              color: Color.menu.text; opacity: 0.5
              font.family: Style.font.iconFamily; font.pixelSize: Style.font.caption
            }
            Text {
              text: "WIND"
              color: Color.menu.text; opacity: 0.5
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
        // wallpaper's colors until the next fetch.
        Connections {
          target: Color
          function onAccentChanged() { spark.requestPaint() }
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
          color: Color.menu.text; opacity: 0.5
          font.family: Style.font.family; font.pixelSize: Style.font.caption
        }
        Text {
          width: parent.width / 2
          horizontalAlignment: Text.AlignRight
          text: "bars = chance of rain"
          color: Color.menu.text; opacity: 0.5
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
              color: Color.menu.text; opacity: 0.7
              font.family: Style.font.family; font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Text {
              width: Style.space(64)
              anchors.verticalCenter: parent.verticalCenter
              text: "\u{f0597} " + root.n0(modelData.pop) + "%"
              color: Color.menu.text; opacity: 0.6
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

      // Says how the location was determined, never where it is. "timezone"
      // in particular is a coarse, tunnel-proof guess and the user should be
      // able to tell that is what they are looking at.
      Text {
        width: parent.width
        visible: root.report !== null
        horizontalAlignment: Text.AlignRight
        text: {
          var s = root.report ? root.report.source : ""
          var how = s === "manual" ? "manual location"
                  : s === "geoclue" ? "system location"
                  : s === "timezone" ? "timezone estimate"
                  : s === "ipgeo" ? "IP estimate" : ""
          return (root.report && root.report.stale ? "cached · " : "") + how
        }
        color: Color.menu.text; opacity: 0.35
        font.family: Style.font.family; font.pixelSize: Style.font.caption
      }
    }
  }
}
