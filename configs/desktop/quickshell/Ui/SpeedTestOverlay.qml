import QtQuick
import qs.Commons

// speed test overlay shared by network and disk tests
OverlayCard {
  id: root

  required property string fontFamily
  required property bool running
  required property string leftLabel
  required property string rightLabel
  property string unit: "Mbps"
  property real leftValue: 0
  property real rightValue: 0
  property bool leftLive: false
  property bool rightLive: false
  property string error: ""
  property string statusText: ""
  // gauge full-scale steps, smallest first
  property var scaleStops: [100, 250, 500, 1000, 2500, 5000, 10000]
  property real fullScale: scaleStops[0]

  property var leftHist: []
  property var rightHist: []

  signal closeRequested()
  signal runAgainRequested()

  readonly property bool failed: error !== ""

  function resetScale() {
    fullScale = scaleStops[0]
  }

  function expandScale(value) {
    for (var i = 0; i < scaleStops.length; i++) {
      if (value <= scaleStops[i] * 0.92) {
        if (scaleStops[i] > fullScale) fullScale = scaleStops[i]
        return
      }
    }
    fullScale = scaleStops[scaleStops.length - 1]
  }

  onRunningChanged: if (running) { resetScale(); leftHist = []; rightHist = [] }
  onScaleStopsChanged: resetScale()
  onLeftValueChanged: { expandScale(leftValue); if (leftValue > 0) leftHist = Util.historyPush(leftHist, leftValue) }
  onRightValueChanged: { expandScale(rightValue); if (rightValue > 0) rightHist = Util.historyPush(rightHist, rightValue) }

  Behavior on fullScale {
    NumberAnimation { duration: Style.motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
  }

  readonly property color onCard: Color.menu.text
  readonly property color onCardDim: Util.alpha(Color.menu.text, 0.55)
  readonly property color onCardUrgent: Color.urgent

  title: "speed test"
  hints: root.running ? [["ESC", "close"]] : [["ESC", "close"], ["ENTER", "run again"]]
  cardWidth: inner.implicitWidth + chromeWidth
  cardHeight: inner.implicitHeight + chromeHeight
  onDismissed: root.closeRequested()

  // refocus and ignite once actually mapped
  onOpenChanged: {
    if (open) Qt.callLater(function() {
      if (!root.open) return
      keyCatcher.forceActiveFocus()
      leftGauge.ignite()
      rightGauge.ignite()
    })
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true

    Keys.onEscapePressed: root.closeRequested()
    Keys.onReturnPressed: if (!root.running) root.runAgainRequested()
    Keys.onEnterPressed: if (!root.running) root.runAgainRequested()
  }

  Column {
    id: inner
    spacing: Style.spacing.lg

    Row {
      spacing: Style.spacing.xl
      Gauge {
        id: leftGauge
        label: root.leftLabel
        value: root.leftValue
        live: root.leftLive
        history: root.leftHist
      }
      Gauge {
        id: rightGauge
        label: root.rightLabel
        value: root.rightValue
        live: root.rightLive
        history: root.rightHist
      }
    }

    Text {
      width: inner.width
      textFormat: Text.PlainText
      visible: root.statusText !== ""
      text: "> " + root.statusText
      color: root.onCard
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.letterSpacing: Style.headerTracking * 0.4
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      width: inner.width
      textFormat: Text.PlainText
      visible: root.failed
      text: "! " + root.error
      color: root.onCardUrgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignHCenter
    }

    Item {
      width: inner.width
      implicitHeight: runAgain.implicitHeight
      height: implicitHeight
      ActionButton {
        id: runAgain
        anchors.horizontalCenter: parent.horizontalCenter
        label: "run again"
        tint: root.onCard
        enabled: !root.running
        opacity: root.running ? 0 : 1
        onActivated: root.runAgainRequested()

        Behavior on opacity {
          NumberAnimation { duration: Style.motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
        }
      }
    }
  }

  component Gauge: Column {
    id: g

    required property string label
    required property real value
    required property bool live
    property var history: []
    readonly property real gaugeWidth: Style.space(260)

    readonly property bool engaged: live || value > 0

    property real shown: 0
    // the sweep drives the fill, not the numeral
    readonly property real reading: ignition.running ? value : shown
    readonly property real fullScale: root.fullScale
    readonly property real fraction: fullScale > 0 ? Math.max(0, Math.min(1, shown / fullScale)) : 0

    width: gaugeWidth
    spacing: Style.spacing.md
    opacity: engaged ? 1 : 0.5

    Behavior on opacity {
      NumberAnimation { duration: Style.motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
    }

    Behavior on shown {
      enabled: !ignition.running
      NumberAnimation { duration: Style.motion.ambient; easing.type: Style.motion.ambientEasing }
    }

    onValueChanged: {
      if (!ignition.running) shown = value
    }

    function ignite() {
      ignition.restart()
    }

    SequentialAnimation {
      id: ignition
      NumberAnimation { target: g; property: "shown"; to: g.fullScale; duration: Style.motion.ambient; easing.type: Style.motion.ambientEasing }
      NumberAnimation { target: g; property: "shown"; to: 0; duration: Style.motion.ambient; easing.type: Style.motion.ambientEasing }
      onFinished: g.shown = g.value
    }

    PanelSectionHeader {
      width: g.gaugeWidth
      fontFamily: root.fontFamily
      fontSize: Style.font.subtitle
      text: g.label
    }

    // the reading sweeps many times a second: outline, not glow
    Hero {
      value: g.reading < 10
        ? g.reading.toLocaleString(Qt.locale(), 'f', 1)
        : Math.round(g.reading).toLocaleString(Qt.locale(), 'f', 0)
      unit: root.unit
      live: true
    }

    BarGauge {
      width: g.gaugeWidth
      height: Style.space(14)
      segments: 32
      value: g.fraction
      color: Color.accent
    }

    Sparkline {
      width: g.gaugeWidth
      height: Style.space(46)
      values: g.history
      minValue: 0
      maxValue: g.fullScale
      color: Color.accent
    }
  }
}
