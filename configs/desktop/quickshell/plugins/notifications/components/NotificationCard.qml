pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../NotificationLogic.js" as NotificationLogic

BorderSurface {
  id: root

  property string app: ""
  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  property string glyph: ""
  property int urgency: 1
  property double timestamp: 0

  property string variant: "toast"
  readonly property bool isRow: variant === "row"

  property int bodyLines: 3

  property double now: 0

  property var actions: []
  property int groupCount: 1
  property int segmentsLeft: 0
  readonly property int gaugeSegments: 4

  function formatTime(ts, ref) {
    if (!ts) return ""
    var when = new Date(ts * (ts < 1e12 ? 1000 : 1))
    if (ref && Math.round((ref - when.getTime()) / 1000) < 60) return "now"
    var sameDay = when.toDateString() === (ref ? new Date(ref) : new Date()).toDateString()
    return Qt.formatDateTime(when, sameDay ? Util.timeFormat : Util.dayFormat + " " + Util.timeFormat)
  }

  property string fontFamily: Style.font.family

  readonly property bool hovered: hoverTracker.hovered
  readonly property string timeLabel: formatTime(timestamp, now)

  signal closeRequested()
  signal cardClicked()
  signal actionInvoked(string identifier)
  readonly property string smallIconSource: image.length > 0 ? image : Util.iconSource(appIcon)
  readonly property bool hasGlyph: glyph.length > 0
  readonly property bool compactGlyph: hasGlyph && smallIconSource.length === 0 && singleLineToast
  readonly property bool hasSmallIcon: smallIconSource.length > 0
  readonly property bool summaryStartsWithGlyph: NotificationLogic.summaryStartsWithGlyph(summary)
  readonly property bool singleLineToast: sanitizedBody.length === 0
  readonly property bool collapseRedundantIcon: singleLineToast && !hasGlyph && summaryStartsWithGlyph
  readonly property string sanitizedBody: NotificationLogic.sanitizeBody(body, app, appIcon)
  readonly property string styledBody: NotificationLogic.styledBody(body, app, appIcon)

  readonly property real bodyEmphasis: 0.87
  readonly property color bodyColor: Util.alpha(Colors.notifications.text, bodyEmphasis)
  readonly property real edge: isRow ? 0 : Style.surface.borderWidth
  readonly property bool critical: urgency === NotificationLogic.URGENCY_CRITICAL
  readonly property color strokeColor: critical ? Colors.urgent : Util.alpha(Colors.notifications.border, Style.surface.ruleAlpha)

  implicitWidth: root.isRow ? Style.panelWidth.normal : Style.space(420)
  implicitHeight: mainColumn.implicitHeight + edge * 2
  radius: Style.shape.data
  color: isRow && hovered ? Style.hoverFill : "transparent"
  Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
  clip: true

  HoverHandler { id: hoverTracker }

  DockShape {
    id: toastShape
    visible: !root.isRow
    anchors.fill: parent
    fillColor: Colors.notifications.background
    strokeColor: root.strokeColor
  }

  Rectangle {
    visible: root.isRow && root.urgency === NotificationLogic.URGENCY_CRITICAL
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(2)
    height: parent.height - Style.space(8)
    radius: Style.shape.data
    color: Colors.urgent
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        root.closeRequested()
      } else {
        root.cardClicked()
      }
    }
  }

  ColumnLayout {
    id: mainColumn
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: root.edge
    anchors.leftMargin: root.edge
    anchors.rightMargin: root.edge
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.spacing.md
      Layout.rightMargin: Style.spacing.md
      Layout.topMargin: root.singleLineToast ? Style.spacing.xs : Style.spacing.sm
      Layout.bottomMargin: root.singleLineToast ? Style.spacing.xs : Style.spacing.sm
      spacing: root.collapseRedundantIcon ? 0 : (root.compactGlyph ? Style.spacing.sm : Style.spacing.md)

      Item {
        id: smallIconSlot
        Layout.preferredWidth: visible ? (root.isRow ? Style.space(24) : Style.space(32)) : 0
        Layout.preferredHeight: visible ? (root.isRow ? Style.space(24) : Style.space(32)) : 0
        Layout.alignment: Qt.AlignVCenter
        visible: !root.collapseRedundantIcon && !root.compactGlyph && (root.hasSmallIcon || root.hasGlyph) && (root.hasGlyph || smallIconImage.status !== Image.Error)

        Image {
          id: smallIconImage
          anchors.fill: parent
          source: root.smallIconSource
          sourceSize.width: smallIconSlot.width * Screen.devicePixelRatio
          sourceSize.height: smallIconSlot.height * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          visible: !root.hasGlyph || smallIconImage.status === Image.Ready
        }

        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          visible: root.hasGlyph && smallIconImage.status !== Image.Ready
          text: root.glyph
          color: Colors.notifications.text
          font.family: Style.font.iconFamily
          font.pixelSize: Style.font.displayLarge
          layer.enabled: !root.isRow && Style.fx.glow > 0
          layer.effect: Glow {}
        }
      }

      Text {
        textFormat: Text.PlainText
        Layout.alignment: Qt.AlignVCenter
        visible: root.compactGlyph
        text: root.glyph
        color: Colors.notifications.text
        font.family: Style.font.iconFamily
        font.pixelSize: Style.font.icon
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        Layout.rightMargin: Style.spacing.md
        spacing: Style.spacing.xxs

        Row {
          Layout.fillWidth: true
          spacing: Style.spacing.xs
          visible: root.critical || root.app.length > 0 || root.timeLabel.length > 0

          readonly property bool showDot: root.app.length > 0 && root.timeLabel.length > 0
          readonly property real dotSlotWidth: showDot ? dotText.implicitWidth + spacing : 0
          readonly property real criticalSlotWidth: root.critical ? criticalText.implicitWidth + spacing : 0

          Text {
            id: criticalText
            visible: root.critical
            textFormat: Text.PlainText
            text: "! CRITICAL"
            color: Colors.urgentText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Caption {
            width: Math.min(implicitWidth, parent.width - timeText.implicitWidth - parent.dotSlotWidth - parent.criticalSlotWidth - parent.spacing)
            text: root.app.toUpperCase() + (root.groupCount > 1 ? " x" + root.groupCount : "")
            elide: Text.ElideRight
          }
          Caption {
            id: dotText
            visible: parent.showDot
            text: "::"
          }
          Caption {
            id: timeText
            text: root.timeLabel
          }
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: root.summary.length > 0
          text: root.summary
          font.family: root.fontFamily
          color: Colors.notifications.text
          font.pixelSize: Style.font.body
          font.bold: true
          wrapMode: Text.WordWrap
          elide: Text.ElideRight
          maximumLineCount: 2
        }

        Text {
          Layout.fillWidth: true
          Layout.topMargin: Style.spacing.xxs
          visible: root.sanitizedBody.length > 0
          text: root.styledBody
          textFormat: Text.StyledText
          font.family: root.fontFamily
          color: root.bodyColor
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
          elide: Text.ElideRight
          maximumLineCount: Math.max(1, root.bodyLines)
        }

        Flow {
          Layout.fillWidth: true
          Layout.topMargin: Style.spacing.xs
          visible: !root.isRow && root.actions.length > 0
          spacing: Style.spacing.xs

          Repeater {
            model: root.isRow ? [] : root.actions
            Button {
              variant: "action"
              required property var modelData
              text: modelData.text
              foreground: Colors.notifications.text
              onClicked: root.actionInvoked(modelData.id)
            }
          }
        }
      }
    }

    // one unbroken track that empties in quarter steps; dashes this close to the bottom stroke read as gaps in the
    // border
    Rectangle {
      id: gauge
      Layout.fillWidth: true
      Layout.leftMargin: Style.spacing.md
      Layout.rightMargin: Style.spacing.md
      Layout.bottomMargin: Style.spacing.sm
      implicitHeight: Style.spacing.xxs
      visible: !root.isRow && root.segmentsLeft > 0
      radius: Style.shape.data
      color: Util.alpha(gaugeFill.color, Style.emphasis.disabled * 0.5)

      Rectangle {
        id: gaugeFill
        width: gauge.width * Math.min(1, root.segmentsLeft / root.gaugeSegments)
        height: gauge.height
        radius: gauge.radius
        color: root.critical ? Colors.urgent : Colors.accent
        opacity: Style.emphasis.dim
        Behavior on width { NumberAnimation { duration: Style.motion.base; easing.type: Style.motion.fastEasing } }
      }
    }
  }

  Item {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: root.edge + Style.spacing.xs
    anchors.rightMargin: root.edge + Style.shape.chamfer
    width: Style.space(18)
    height: Style.space(18)
    visible: opacity > 0
    opacity: root.hovered ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "x"
      color: closeArea.containsMouse ? Colors.notifications.text : Util.alpha(Colors.notifications.text, Style.emphasis.dim)
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
    }

    MouseArea {
      id: closeArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.closeRequested()
    }
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: Colors.textDim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  HudFrame { shown: !root.isRow; chamfer: toastShape.cut; chamferCorner: toastShape.cutCorner }
  Scanlines { shown: !root.isRow }
}
