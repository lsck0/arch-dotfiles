import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// speed test overlay shared by network and disk tests
PanelWindow {
  id: root

  required property string fontFamily
  required property bool running
  required property string leftLabel
  required property string rightLabel
  property string unit: "Mbps"
  property string title: ""
  property string layerNamespace: "omarchy-speed-test"
  property string runAgainTooltip: "Measure again"
  property real leftValue: 0
  property real rightValue: 0
  property bool leftLive: false
  property bool rightLive: false
  property string error: ""
  property string statusText: ""
  property bool open: false
  // gauge full-scale steps, smallest first
  property var scaleStops: [100, 250, 500, 1000, 2500, 5000, 10000]
  property real fullScale: scaleStops[0]

  property var leftHist: []
  property var rightHist: []
  function _push(arr, v) { var a = arr.slice(); a.push(v); if (a.length > 60) a.shift(); return a }

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
  onLeftValueChanged: { expandScale(leftValue); if (leftValue > 0) leftHist = _push(leftHist, leftValue) }
  onRightValueChanged: { expandScale(rightValue); if (rightValue > 0) rightHist = _push(rightHist, rightValue) }

  Behavior on fullScale {
    NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
  }

  readonly property color cardBackground: Color.menu.background
  readonly property color onCard: Color.menu.text
  readonly property color onCardDim: Util.alpha(Color.menu.text, 0.55)
  readonly property color onCardUrgent: Color.urgent

  visible: open
  // refocus and ignite once actually mapped
  onOpenChanged: {
    if (open) Qt.callLater(function() {
      if (!root.open) return
      keyCatcher.forceActiveFocus()
      leftGauge.ignite()
      rightGauge.ignite()
    })
  }
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: root.layerNamespace
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  Rectangle {
    anchors.fill: parent
    color: Color.menu.scrim

    MouseArea {
      anchors.fill: parent
      onClicked: root.closeRequested()
    }
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true

    Keys.onEscapePressed: root.closeRequested()
    Keys.onReturnPressed: if (!root.running) root.runAgainRequested()
    Keys.onEnterPressed: if (!root.running) root.runAgainRequested()

    Item {
      anchors.fill: parent
      scale: Math.min(1,
        (keyCatcher.width - Style.space(32)) / Math.max(1, card.width),
        (keyCatcher.height - Style.space(32)) / Math.max(1, card.height))

      // swallow clicks so only the scrim dismisses
      MouseArea {
        anchors.centerIn: parent
        width: card.width + Style.space(48)
        height: card.height + Style.space(48)
        onClicked: {}
      }

      BorderSurface {
        id: card
        anchors.centerIn: parent
        color: root.cardBackground
        borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
        padding: Style.space(24)
        radius: Style.cornerRadius
        width: inner.implicitWidth + card.contentLeftInset + card.contentRightInset
        height: inner.implicitHeight + card.contentTopInset + card.contentBottomInset

        Column {
          id: inner
          x: card.contentLeftInset
          y: card.contentTopInset
          spacing: Style.space(16)

          Item {
            width: inner.width
            implicitHeight: titleRow.implicitHeight
            height: implicitHeight
            Row {
              id: titleRow
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: ">"
                color: Color.accent
                opacity: Style.emphasis.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }
              PanelSectionHeader {
                anchors.verticalCenter: parent.verticalCenter
                fontFamily: root.fontFamily
                fontSize: Style.font.title
                text: root.title !== "" ? root.title : "SPEED TEST"
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "_"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
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
                SequentialAnimation on opacity {
                  running: true
                  loops: Animation.Infinite
                  NumberAnimation { to: 0.15; duration: 520 }
                  NumberAnimation { to: 1.0; duration: 520 }
                }
              }
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: titleRow.verticalCenter
              textFormat: Text.PlainText
              text: "[ - o x ]"
              color: Color.accent
              opacity: Style.emphasis.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: Style.headerTracking * 0.5
            }
          }
          PanelSeparator { width: inner.width }

          Row {
            spacing: Style.space(28)
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
            Button {
              id: runAgain
              anchors.horizontalCenter: parent.horizontalCenter
              text: "[ RUN AGAIN ]"
              tooltipText: root.runAgainTooltip
              bordered: true
              enabled: !root.running
              opacity: root.running ? 0 : 1
              foreground: root.onCard
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(14)
              verticalPadding: Style.space(4)
              onClicked: root.runAgainRequested()

              Behavior on opacity {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
              }
            }
          }
        }

        Scanlines { }
        HudFrame { }
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
    spacing: Style.space(10)
    opacity: engaged ? 1 : 0.5

    Behavior on opacity {
      NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }

    Behavior on shown {
      enabled: !ignition.running
      NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
    }

    onValueChanged: {
      if (!ignition.running) shown = value
    }

    function ignite() {
      ignition.restart()
    }

    SequentialAnimation {
      id: ignition
      NumberAnimation { target: g; property: "shown"; to: g.fullScale; duration: 550; easing.type: Easing.InOutCubic }
      NumberAnimation { target: g; property: "shown"; to: 0; duration: 650; easing.type: Easing.OutCubic }
      onFinished: g.shown = g.value
    }

    PanelSectionHeader {
      width: g.gaugeWidth
      fontFamily: root.fontFamily
      fontSize: Style.font.subtitle
      text: g.label
    }

    Row {
      spacing: Style.spacing.xs
      Text {
        id: heroNum
        anchors.bottom: parent.bottom
        textFormat: Text.PlainText
        text: g.reading < 10
          ? g.reading.toLocaleString(Qt.locale(), 'f', 1)
          : Math.round(g.reading).toLocaleString(Qt.locale(), 'f', 0)
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Math.round(g.gaugeWidth * 0.24)
        font.bold: true
        font.letterSpacing: Style.displayTracking
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
        anchors.bottom: heroNum.bottom
        anchors.bottomMargin: Math.round(g.gaugeWidth * 0.05)
        textFormat: Text.PlainText
        text: root.unit
        color: root.onCardDim
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }
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
