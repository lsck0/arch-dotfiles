pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "weather"

  property var report: null
  property string failNote: ""
  property real updatedMs: 0
  readonly property var retryDelaysS: [5, 10, 20, 40, 80, 160, 300]
  property int forecastTries: 0
  property int alertsTries: 0

  function retryDelayMs(tries) { return retryDelaysS[Math.min(tries, retryDelaysS.length - 1)] * 1000 }
  readonly property int staleAfterMs: 2 * 60 * 60 * 1000

  readonly property var current: report && report.current ? report.current : null
  readonly property var hourly: report && report.hourly ? report.hourly : []
  readonly property var daily: report && report.daily ? report.daily : []
  readonly property var forecast: daily.length > 1 ? daily.slice(1) : []
  readonly property var hourlyTemps: hourly.map(function (h) { return Number(h.temp) })
  readonly property real hourlyTempMin: hourlyTemps.length > 0 ? Math.min.apply(null, hourlyTemps) : 0
  readonly property real hourlyTempMax: hourlyTemps.length > 0 ? Math.max.apply(null, hourlyTemps) : 0
  readonly property string units: report && report.units ? report.units.temp : "\u00b0C"
  readonly property string windUnits: report && report.units ? report.units.wind : "km/h"

  readonly property var wmo: [
    [0, 0, "\u{f0599}", "\u{f0594}", "Clear"],
    [1, 1, "\u{f0595}", "\u{f0f31}", "Mainly clear"],
    [2, 2, "\u{f0595}", "\u{f0f31}", "Partly cloudy"],
    [3, 3, "\u{f0590}", "\u{f0590}", "Overcast"],
    [45, 48, "\u{f0591}", "\u{f0591}", "Fog"],
    [51, 57, "\u{f0597}", "\u{f0597}", "Drizzle"],
    [61, 65, "\u{f0596}", "\u{f0596}", "Rain"],
    [66, 67, "\u{f067f}", "\u{f067f}", "Freezing rain"],
    [71, 77, "\u{f0598}", "\u{f0598}", "Snow"],
    [80, 82, "\u{f0596}", "\u{f0596}", "Showers"],
    [85, 86, "\u{f0598}", "\u{f0598}", "Snow showers"],
    [95, 95, "\u{f067e}", "\u{f067e}", "Thunderstorm"],
    [96, 99, "\u{f0592}", "\u{f0592}", "Thunderstorm, hail"]
  ]

  function wmoFor(code) {
    var c = Number(code)
    for (let i = 0; i < wmo.length; i++) if (c >= wmo[i][0] && c <= wmo[i][1]) return wmo[i]
    return [c, c, "\u{f0590}", "\u{f0590}", "--"]
  }

  function iconFor(code, isDay) { return wmoFor(code)[Number(isDay) === 0 ? 3 : 2] }
  function labelFor(code) { return wmoFor(code)[4] }

  function compass(deg) {
    var pts = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    return pts[Math.round(Number(deg) / 45) % 8]
  }

  function t(v) { return (Math.round(Number(v) * 10) / 10) + "\u00b0" }
  function n0(v) { return Math.round(Number(v)) }

  implicitWidth: trigger.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  property var alerts: []
  property int countryOthers: 0

  readonly property var topAlert: alerts.length > 0 ? alerts[0] : null
  readonly property bool alertProminent: topAlert !== null && Number(topAlert.level) >= 3

  function alertColor(level) {
    return [Colors.semantic.warn, Colors.semantic.alertOrange, Colors.semantic.alertRed][Number(level) - 2] || Colors.menu.text
  }
  function alertLabel(level) { return ["YELLOW", "ORANGE", "RED"][Number(level) - 2] || "MINOR" }

  property var field: ({})
  readonly property var fieldCells: field.cells || []
  readonly property bool hasField: fieldCells.length > 0

  property var radar: ({})
  readonly property var radarFrames: radar.frames || []
  readonly property int radarSpanKm: radar.spanKm || 0

  readonly property real radarReachKm: radarSpanKm > 0 ? radarSpanKm / 2 : 0

  readonly property int radarRingStepKm: {
    if (radarReachKm <= 0) return 0
    var target = radarReachKm / 3
    var nice = [5, 10, 20, 25, 50, 100, 200, 250, 500, 1000]
    var chosen = nice[0]
    for (let i = 0; i < nice.length; i++)
      if (nice[i] <= target) chosen = nice[i]
    return chosen
  }

  readonly property var radarRingsKm: {
    var out = []
    if (radarRingStepKm <= 0) return out
    for (let km = radarRingStepKm; km <= radarReachKm; km += radarRingStepKm)
      out.push(km)
    return out
  }
  property int radarIndex: 0
  onRadarChanged: radarIndex = 0
  property bool radarPlaying: true
  readonly property var radarFrame: radarFrames.length > 0
    ? radarFrames[Math.min(radarIndex, radarFrames.length - 1)] : null

  JsonProcess {
    id: forecastProc
    command: [Paths.barWidget("weather.nu"), "forecast"]
    minAgeMs: 60 * 1000
    intervalMs: panel.visible ? 30 * 60 * 1000 : 60 * 60 * 1000
    onParsed: function (d) {
      if (d.ok) {
        root.report = d
        root.updatedMs = Date.now() - (d.stale ? Number(d.ageMin || 0) * 60000 : 0)
      }
      if (d.ok && !d.stale) {
        root.failNote = ""
        root.forecastTries = 0
        forecastRetry.stop()
        return
      }
      root.failNote = String(d.error || "no answer")
      forecastRetry.interval = root.retryDelayMs(root.forecastTries)
      forecastRetry.restart()
    }
    onFailed: {
      root.failNote = "no answer"
      forecastRetry.interval = root.retryDelayMs(root.forecastTries)
      forecastRetry.restart()
    }
  }

  Timer {
    id: forecastRetry
    onTriggered: { root.forecastTries += 1; forecastProc.run() }
  }

  JsonProcess {
    id: alertsProc
    command: [Paths.barWidget("weather.nu"), "alerts"]
    minAgeMs: 60 * 1000
    intervalMs: panel.visible ? 30 * 60 * 1000 : 60 * 60 * 1000
    onParsed: function (d) {
      if (!d.ok) {
        alertsRetry.interval = root.retryDelayMs(root.alertsTries)
        alertsRetry.restart()
        return
      }
      root.alertsTries = 0
      alertsRetry.stop()
      root.alerts = d.alerts || []
      root.countryOthers = d.countryOthers || 0
    }
    onFailed: {
      alertsRetry.interval = root.retryDelayMs(root.alertsTries)
      alertsRetry.restart()
    }
  }

  Timer {
    id: alertsRetry
    onTriggered: { root.alertsTries += 1; alertsProc.run() }
  }

  JsonProcess {
    id: radarProc
    command: [Paths.barWidget("weather.nu"), "radar"]
    intervalMs: panel.visible ? 10 * 60 * 1000 : 0
    onParsed: function (d) {
      if (d.radar.ok) root.radar = d.radar
      if (d.field.ok) root.field = d.field
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.shape.data
    color: hoverArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
  }

  Row {
    id: trigger
    anchors.centerIn: parent
    spacing: Style.spacing.xs

    Text {
      id: alertGlyph
      anchors.verticalCenter: parent.verticalCenter
      visible: root.alertProminent
      textFormat: Text.PlainText
      text: "\u{f0026}"
      color: root.topAlert ? root.alertColor(root.topAlert.level) : Colors.urgent
      font.family: root.bar ? root.bar.iconFontFamily : Style.font.iconFamily
      font.pixelSize: Style.font.icon
      layer.enabled: Style.fx.glow > 0 && root.alertProminent
      layer.effect: Glow { shadowColor: root.topAlert ? root.alertColor(root.topAlert.level) : Colors.urgent }

      readonly property int flashCount: 3
      SequentialAnimation on opacity {
        id: alertFlash
        running: false
        loops: alertGlyph.flashCount
        NumberAnimation { to: Style.emphasis.faint; duration: Style.motion.base }
        NumberAnimation { to: 1.0; duration: Style.motion.base }
      }
      Connections {
        target: root
        function onAlertProminentChanged() { if (root.alertProminent && Style.motion.enabled) alertFlash.restart() }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.current ? root.iconFor(root.current.code, root.current.isDay) : "\u{f0590}"
      color: root.bar ? root.bar.barForeground : Colors.foreground
      font.family: root.bar ? root.bar.iconFontFamily : Style.font.iconFamily
      font.pixelSize: Style.font.icon
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      visible: root.current !== null
      text: root.current ? root.t(root.current.temp) : ""
      color: root.bar ? root.bar.barForeground : Colors.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      opacity: Style.emphasis.strong
    }
    DataState {
      anchors.verticalCenter: parent.verticalCenter
      loading: forecastProc.running
      error: root.updatedMs > 0 ? root.failNote : ""
      updatedMs: root.updatedMs
      staleAfterMs: root.staleAfterMs
    }
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    onEntered: if (root.bar) root.bar.hoverOpen(root.moduleName)
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    title: "WEATHER"
    onOpened: { forecastProc.refresh(); alertsProc.refresh() }
    implicitWidth: Style.panelWidth.wide
    implicitHeight: Math.min(content.implicitHeight, maxBodyHeight) + padding * 2 + titleInset

    component Stat: Column {
      id: stat
      property string glyph: ""
      property real glyphRotation: 0
      property string caption: ""
      property string value: ""
      width: statGrid.cellWidth
      spacing: Style.spacing.xxs
      Row {
        spacing: Style.spacing.xs
        Text {
          text: stat.glyph
          rotation: stat.glyphRotation
          color: Colors.menu.text; opacity: Style.emphasis.faint
          font.family: Style.font.iconFamily; font.pixelSize: Style.font.caption
        }
        Text {
          text: stat.caption
          color: Colors.menu.text
          font.family: Style.font.family; font.pixelSize: Style.font.caption
        }
      }
      Text {
        width: stat.width
        text: stat.value
        color: Colors.menu.text
        font.family: Style.font.family; font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }

    Timer {
      interval: 250
      repeat: true
      running: panel.visible && root.radarPlaying && root.radarFrames.length > 1
      onTriggered: root.radarIndex = (root.radarIndex + 1) % root.radarFrames.length
    }

    Flickable {
      width: parent.width
      height: Math.min(content.implicitHeight, panel.maxBodyHeight)
      contentWidth: width
      contentHeight: content.implicitHeight
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds
      clip: true

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.sm

        Column {
          width: parent.width
          spacing: Style.spacing.xs
          visible: root.alerts.length > 0

          Repeater {
            model: root.alerts
            delegate: Rectangle {
              id: alertItem
              required property var modelData
              width: content.width
              height: alertRow.implicitHeight + Style.spacing.xs * 2
              radius: Style.shape.data
              color: Util.alpha(root.alertColor(alertItem.modelData.level), Style.tintFillAlpha)
              Rectangle {
                width: Style.space(3)
                height: parent.height
                radius: Style.shape.data
                color: root.alertColor(alertItem.modelData.level)
              }

              Column {
                id: alertRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.spacing.sm
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xxs

                Row {
                  width: parent.width
                  spacing: Style.spacing.xs
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f0026}"
                    color: root.alertColor(alertItem.modelData.level)
                    font.family: Style.font.iconFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.alertLabel(alertItem.modelData.level)
                    color: root.alertColor(alertItem.modelData.level)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: Style.headerTracking
                    font.bold: true
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: alertItem.modelData.event || alertItem.modelData.kind || "Weather warning"
                    color: Colors.menu.text
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
                    if (Number(alertItem.modelData.startsIn) > 0) bits.push("starts in " + Util.span(alertItem.modelData.startsIn))
                    if (alertItem.modelData.endsIn !== null) bits.push("ends in " + Util.span(alertItem.modelData.endsIn))
                    bits.push(alertItem.modelData.scope === "here" ? "your area" : "your region")
                    if (alertItem.modelData.certainty) bits.push(String(alertItem.modelData.certainty).toLowerCase())
                    return bits.join(" :: ")
                  }
                  color: Colors.menu.text
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
            color: Colors.menu.text
            opacity: Style.emphasis.disabled
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator { visible: root.alerts.length > 0 }

        Row {
          width: parent.width
          spacing: Style.spacing.sm

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.current ? root.iconFor(root.current.code, root.current.isDay) : "\u{f0590}"
            color: Colors.accent
            font.family: Style.font.iconFamily
            font.pixelSize: Style.font.displayLarge
            layer.enabled: Style.fx.glow > 0
            layer.effect: Glow {}
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xxs
            Text {
              text: root.current ? root.t(root.current.temp) : "--"
              color: Colors.menu.text
              font.family: Style.font.family; font.pixelSize: Style.font.display
              font.letterSpacing: Style.displayTracking
              layer.enabled: Style.fx.glow > 0
              layer.effect: Glow {}
            }
            Text {
              text: root.current
                ? root.labelFor(root.current.code) + " :: feels " + root.t(root.current.feelsLike)
                : (root.failNote ? "No data yet :: " + root.failNote + ", retrying" : "--")
              color: Colors.menu.text; opacity: Style.emphasis.dim
              font.family: Style.font.family; font.pixelSize: Style.font.caption
            }
          }
        }

        Grid {
          id: statGrid
          width: parent.width
          columns: 4
          rowSpacing: Style.spacing.xs
          columnSpacing: Style.spacing.xs
          visible: root.current !== null
          readonly property real cellWidth: (width - columnSpacing * (columns - 1)) / columns

          Stat {
            glyph: "\u{f0597}"; caption: "RAIN NOW"
            value: root.current ? (Math.round(Number(root.current.precip) * 10) / 10) + " mm" : "--"
          }
          Stat {
            glyph: "\u{f054a}"; caption: "RAIN 1H"
            value: root.hourly.length > 0 ? root.n0(root.hourly[0].pop) + "%" : "--"
          }
          Stat {
            glyph: "\u{f058e}"; caption: "HUMIDITY"
            value: root.current ? root.n0(root.current.humidity) + "%" : "--"
          }
          Stat {
            glyph: "\u{f0590}"; caption: "CLOUD"
            value: root.current ? root.n0(root.current.cloud) + "%" : "--"
          }

          // arrow points where the wind goes, text says where it comes from
          Stat {
            glyph: "\u{f0390}"; glyphRotation: root.current ? Number(root.current.windDir) + 180 : 0
            caption: "WIND"
            value: root.current
              ? root.n0(root.current.wind) + " " + root.windUnits + " " + root.compass(root.current.windDir)
              : "--"
          }
          Stat {
            glyph: "\u{f059d}"; caption: "GUSTS"
            value: root.current ? root.n0(root.current.gust) + " " + root.windUnits : "--"
          }
          Stat {
            glyph: "\u{f029a}"; caption: "PRESSURE"
            value: root.current ? root.n0(root.current.pressure) + " hPa" : "--"
          }
          Stat {
            glyph: "\u{f0599}"; caption: "UV"
            value: root.current ? (Math.round(Number(root.current.uv) * 10) / 10) : "--"
          }
        }

        PanelSeparator {}
        PanelSectionHeader {
          text: "NEXT 24 HOURS" + (root.hourly.length > 0 ? " :: " + root.t(root.hourlyTempMin) + " .. " + root.t(root.hourlyTempMax) : "")
        }

        Sparkline {
          width: parent.width
          height: Style.space(64)
          visible: root.hourly.length > 0
          color: Colors.menu.text
          glow: true
          // the 0..1 defaults would push temps off-canvas
          minValue: root.hourlyTempMin - 1
          maxValue: root.hourlyTempMax + 1
          values: root.hourlyTemps
        }

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
                  id: hourBar
                  required property var modelData
                  width: (hourlyBars.width - (root.hourly.length - 1)) / Math.max(1, root.hourly.length)
                  height: hourlyBars.height
                  Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Math.max(1, parent.height * Math.max(0, Math.min(100, Number(hourBar.modelData.pop) || 0)) / 100)
                    color: Util.alpha(Colors.accent, 0.55)
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
                id: hourTick
                required property var modelData
                required property int index
                width: (hourlyBars.width - (root.hourly.length - 1)) / Math.max(1, root.hourly.length)
                spacing: 0
                Text {
                  text: hourTick.index % 6 === 0 ? root.iconFor(hourTick.modelData.code, 1) : ""
                  color: Colors.accent
                  font.family: Style.font.iconFamily; font.pixelSize: Style.font.iconSmall
                }
                Text {
                  text: hourTick.index % 6 === 0 ? hourTick.modelData.h : ""
                  color: Colors.menu.text; opacity: Style.emphasis.faint
                  font.family: Style.font.family; font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        PanelSeparator {}
        PanelSectionHeader { text: "3-DAY FORECAST" }

        Row {
          width: parent.width
          spacing: Style.spacing.xs

          Repeater {
            model: root.forecast
            delegate: Rectangle {
              id: dayTile
              required property var modelData
              width: (content.width - Style.spacing.xs * (root.forecast.length - 1)) / Math.max(1, root.forecast.length)
              implicitHeight: tile.implicitHeight + Style.spacing.sm * 2
              radius: Style.shape.data
              color: Style.normalFill

              HudFrame {}

              Column {
                id: tile
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Style.spacing.xs
                anchors.rightMargin: Style.spacing.xs
                anchors.topMargin: Style.spacing.sm
                spacing: Style.spacing.xs

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: dayTile.modelData.label
                  color: Colors.accent
                  font.family: Style.font.family; font.pixelSize: Style.font.caption
                  font.bold: true
                  font.capitalization: Font.AllUppercase
                  font.letterSpacing: Style.headerTracking
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: dayTile.modelData.windy ? "\u{f059d}" : root.iconFor(dayTile.modelData.code, 1)
                  color: Colors.menu.text
                  font.family: Style.font.iconFamily; font.pixelSize: Style.font.heading
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: dayTile.modelData.windy ? "Windy" : root.labelFor(dayTile.modelData.code)
                  color: Colors.menu.text; opacity: Style.emphasis.dim
                  font.family: Style.font.family; font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: root.t(dayTile.modelData.hi) + "  " + root.t(dayTile.modelData.lo)
                  color: Colors.menu.text
                  font.family: Style.font.family; font.pixelSize: Style.font.caption
                }
                BarGauge {
                  width: parent.width
                  height: Style.spacing.xs
                  segments: 8
                  value: Math.max(0, Math.min(100, Number(dayTile.modelData.pop) || 0)) / 100
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: "\u{f0597} " + root.n0(dayTile.modelData.pop) + "%"
                  color: Colors.menu.text; opacity: Style.emphasis.dim
                  font.family: Style.font.iconFamily; font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        PanelSeparator {}
        PanelSectionHeader {
          text: "RADAR" + (root.radarSpanKm > 0 ? " :: " + root.radarSpanKm + " km across" : "")
        }

        Item {
          id: radarBox
          width: parent.width
          height: Math.round(width * 0.62)
          visible: root.radarFrames.length > 0
          clip: true

          readonly property real imgSize: width
          readonly property real yOffset: (height - imgSize) / 2

          Image {
            x: 0
            y: radarBox.yOffset
            width: radarBox.imgSize
            height: radarBox.imgSize
            source: root.radarFrame ? Util.fileUrl(root.radarFrame.file) : ""
            sourceSize.width: Math.ceil(width * Screen.devicePixelRatio)
            sourceSize.height: Math.ceil(height * Screen.devicePixelRatio)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            cache: true
          }

          Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: Style.shape.data
            border.width: Style.normalBorderWidth
            border.color: Util.alpha(Colors.accent, Style.hoverBorderAlpha)
          }

          Canvas {
            id: fieldCanvas
            anchors.fill: parent
            antialiasing: true
            renderStrategy: Canvas.Threaded
            renderTarget: Canvas.FramebufferObject

            readonly property var cells: root.fieldCells
            readonly property var rings: root.radarRingsKm
            // quoted, canvas drops unquoted families with spaces; canvas text is no binding, so a change repaints
            readonly property string labelFont: Style.font.caption + 'px "' + Style.font.family + '"'
            onCellsChanged: requestPaint()
            onRingsChanged: requestPaint()
            onLabelFontChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()

            HudFrame {}

            Connections {
              target: Colors
              function onForegroundChanged() { fieldCanvas.requestPaint() }
              function onAccentChanged() { fieldCanvas.requestPaint() }
            }

            function bilinear(field, n, gx, gy) {
              var x = Math.max(0, Math.min(n - 1.0001, gx))
              var y = Math.max(0, Math.min(n - 1.0001, gy))
              var x0 = Math.floor(x), y0 = Math.floor(y)
              var fx = x - x0, fy = y - y0
              return field[y0 * n + x0] * (1 - fx) * (1 - fy)
                   + field[y0 * n + x0 + 1] * fx * (1 - fy)
                   + field[(y0 + 1) * n + x0] * (1 - fx) * fy
                   + field[(y0 + 1) * n + x0 + 1] * fx * fy
            }

            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              var cells = root.fieldCells
              if (!cells || cells.length === 0) return

              var n = Math.round(Math.sqrt(cells.length))
              if (n < 2 || n * n !== cells.length) return

              var S = radarBox.imgSize
              var oy = radarBox.yOffset
              function px(u) { return u * S }
              function py(v) { return oy + v * S }
              var level
              function lerp(p, q, vp, vq) { return p + (q - p) * ((level - vp) / (vq - vp)) }
              function seg(p, q) { ctx.moveTo(p.x, p.y); ctx.lineTo(q.x, q.y) }

              var values = []
              var hasPressure = true
              for (let i = 0; i < cells.length; i++) {
                if (cells[i].hpa === undefined) { hasPressure = false; break }
                values.push(Number(cells[i].hpa))
              }

              if (hasPressure && root.field.pressureMax - root.field.pressureMin >= 0.8) {
                let isobarStep = 1.0
                let firstIsobar = Math.ceil(root.field.pressureMin / isobarStep) * isobarStep
                ctx.lineWidth = 1
                ctx.strokeStyle = Colors.menu.text
                ctx.globalAlpha = 0.42
                let sub = 6
                let cellsAcross = (n - 1) * sub
                for (level = firstIsobar; level <= root.field.pressureMax; level += isobarStep) {
                  ctx.beginPath()
                  for (let msRow = 0; msRow < cellsAcross; msRow++) {
                    for (let msCol = 0; msCol < cellsAcross; msCol++) {
                      let gx0 = msCol / sub, gy0 = msRow / sub
                      let gx1 = (msCol + 1) / sub, gy1 = (msRow + 1) / sub
                      let a = bilinear(values, n, gx0, gy0)
                      let b = bilinear(values, n, gx1, gy0)
                      let c = bilinear(values, n, gx1, gy1)
                      let d = bilinear(values, n, gx0, gy1)
                      let idx = (a > level ? 8 : 0) | (b > level ? 4 : 0)
                              | (c > level ? 2 : 0) | (d > level ? 1 : 0)
                      if (idx === 0 || idx === 15) continue

                      let px0 = px(gx0 / (n - 1)), px1 = px(gx1 / (n - 1))
                      let py0 = py(gy0 / (n - 1)), py1 = py(gy1 / (n - 1))
                      let top = { x: lerp(px0, px1, a, b), y: py0 }
                      let right = { x: px1, y: lerp(py0, py1, b, c) }
                      let bottom = { x: lerp(px0, px1, d, c), y: py1 }
                      let left = { x: px0, y: lerp(py0, py1, a, d) }

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

              var ux = [], vy = []
              for (let ci = 0; ci < cells.length; ci++) {
                let sp = Number(cells[ci].wind) || 0
                let rr0 = (Number(cells[ci].dir) + 180) * Math.PI / 180
                ux.push(Math.sin(rr0) * sp)
                vy.push(-Math.cos(rr0) * sp)
              }

              var maxWind = 1
              for (let w = 0; w < cells.length; w++)
                maxWind = Math.max(maxWind, Number(cells[w].wind) || 0)

              var density = 17
              var latticeStep = S / density
              var arrowReach = latticeStep * 0.28

              ctx.strokeStyle = Colors.accent
              ctx.fillStyle = Colors.accent
              ctx.lineWidth = 1

              for (let gy = 0; gy < density; gy++) {
                for (let gx = 0; gx < density; gx++) {
                  let fu = (gx + 0.5) / density
                  let fv = (gy + 0.5) / density
                  let x = px(fu), y = py(fv)
                  if (y < -arrowReach || y > height + arrowReach) continue

                  let sx = bilinear(ux, n, fu * (n - 1), fv * (n - 1))
                  let sy = bilinear(vy, n, fu * (n - 1), fv * (n - 1))
                  let speed = Math.sqrt(sx * sx + sy * sy)
                  if (speed < 0.01) continue
                  let dx = sx / speed, dy = sy / speed

                  let strength = Math.min(1, speed / maxWind)
                  let shaped = Math.sqrt(strength)
                  let len = arrowReach * (0.55 + 0.45 * shaped)
                  ctx.globalAlpha = 0.13 + 0.29 * shaped

                  let tipX = x + dx * len, tipY = y + dy * len
                  ctx.beginPath()
                  ctx.moveTo(x - dx * len, y - dy * len)
                  ctx.lineTo(tipX, tipY)
                  ctx.stroke()

                  let head = Math.max(1.5, arrowReach * 0.46)
                  let ang = Math.atan2(dx, -dy)
                  let la = ang + Math.PI * 0.82, ra = ang - Math.PI * 0.82
                  ctx.beginPath()
                  ctx.moveTo(tipX, tipY)
                  ctx.lineTo(tipX + Math.sin(la) * head, tipY - Math.cos(la) * head)
                  ctx.lineTo(tipX + Math.sin(ra) * head, tipY - Math.cos(ra) * head)
                  ctx.closePath()
                  ctx.fill()
                }
              }
              ctx.globalAlpha = 1

              var centreX = px(0.5), centreY = py(0.5)
              var reachKm = Number(root.radarReachKm) || 0
              var rings = root.radarRingsKm
              ctx.textAlign = "center"
              ctx.font = fieldCanvas.labelFont
              for (let r = 0; r < rings.length; r++) {
                let km = rings[r]
                let rad = S / 2 * (Number(km) / Math.max(1, reachKm))
                // ctx.arc refuses a non-finite or negative radius
                if (!isFinite(rad) || rad <= 0) continue
                ctx.strokeStyle = Colors.menu.text
                ctx.globalAlpha = r === 0 ? 0.26 : 0.15
                ctx.lineWidth = 1
                ctx.beginPath()
                ctx.arc(centreX, centreY, rad, 0, Math.PI * 2)
                ctx.stroke()

                let label = km + " km"
                let lw = ctx.measureText(label).width
                ctx.globalAlpha = 1
                ctx.fillStyle = Colors.surface
                ctx.fillRect(centreX - lw / 2 - 4, centreY - rad - Style.font.caption * 0.80,
                             lw + 8, Style.font.caption * 1.30)
                ctx.fillStyle = Colors.menu.text
                ctx.globalAlpha = 0.5
                ctx.fillText(label, centreX, centreY - rad + Style.font.caption * 0.28)
              }
              ctx.globalAlpha = 1

              var markerR = Math.max(2, (Number(S) || 0) * 0.006)
              ctx.beginPath()
              ctx.arc(centreX, centreY, markerR + 1.8, 0, Math.PI * 2)
              ctx.fillStyle = Colors.surface
              ctx.globalAlpha = 0.9
              ctx.fill()
              ctx.globalAlpha = 1
              ctx.beginPath()
              ctx.arc(centreX, centreY, markerR, 0, Math.PI * 2)
              ctx.fillStyle = Colors.accent
              ctx.fill()

              var cxc = Math.round(width * 0.115)
              var cyc = Math.round(height * 0.78)
              var rr = Math.max(4, Math.min(width, height) * 0.075)

              ctx.beginPath()
              ctx.arc(cxc, cyc, rr + Style.space(3), 0, Math.PI * 2)
              ctx.fillStyle = Colors.surface
              ctx.globalAlpha = 0.85
              ctx.fill()

              ctx.strokeStyle = Colors.menu.text
              ctx.lineWidth = 1
              ctx.globalAlpha = 0.28
              ctx.beginPath()
              ctx.arc(cxc, cyc, rr, 0, Math.PI * 2)
              ctx.stroke()

              ctx.globalAlpha = 0.4
              for (let q = 0; q < 4; q++) {
                let qa = q * Math.PI / 2
                let inner = rr - (q === 0 ? rr * 0.45 : rr * 0.2)
                ctx.beginPath()
                ctx.moveTo(cxc + Math.sin(qa) * inner, cyc - Math.cos(qa) * inner)
                ctx.lineTo(cxc + Math.sin(qa) * rr, cyc - Math.cos(qa) * rr)
                ctx.stroke()
              }

              ctx.globalAlpha = 0.9
              ctx.fillStyle = Colors.accent
              ctx.beginPath()
              ctx.moveTo(cxc, cyc - rr * 0.6)
              ctx.lineTo(cxc - rr * 0.19, cyc + rr * 0.15)
              ctx.lineTo(cxc + rr * 0.19, cyc + rr * 0.15)
              ctx.closePath()
              ctx.fill()

              ctx.font = fieldCanvas.labelFont
              ctx.textAlign = "center"
              ctx.fillStyle = Colors.menu.text
              ctx.globalAlpha = 0.6
              ctx.fillText("N", cxc, cyc - rr - Style.space(4))
              ctx.globalAlpha = 1
            }
          }

          Scanlines {}
        }

        Row {
          width: parent.width
          visible: root.radarFrames.length > 0
          spacing: Style.spacing.xs

          PanelActionButton {
            iconText: root.radarPlaying ? "\u{f04c}" : "\u{f04b}"
            tooltipText: root.radarPlaying ? "Pause radar" : "Play radar"
            size: Style.space(22)
            fontSize: Style.font.caption
            onClicked: root.radarPlaying = !root.radarPlaying
          }

          Slider {
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
              return m === 0 ? "now" : Util.ago(-m)
            }
            color: Colors.menu.text
            opacity: root.radarFrame && root.radarFrame.forecast ? 0.85 : 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          width: parent.width
          visible: root.radarFrames.length === 0
          text: radarProc.running ? "Loading radar..." : "Radar unavailable"
          color: Colors.menu.text
          opacity: Style.emphasis.disabled
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          visible: root.field.pressureMax > 0
          horizontalAlignment: Text.AlignRight
          text: Number(root.field.pressureMin).toFixed(0) + ".." + Number(root.field.pressureMax).toFixed(0) + " " + root.field.pressureUnits
          color: Colors.menu.text
          opacity: Style.emphasis.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
