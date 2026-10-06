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
  // nerd font glyph shown when no icon is set
  property string glyph: ""
  // low=0, normal=1, critical=2
  property int urgency: 1
  property double timestamp: 0

  // "toast" or "row" (panel list entry)
  property string variant: "toast"
  readonly property bool isRow: variant === "row"

  property int bodyLines: 3

  property double now: 0

  // "now" under a minute, the time today, else the date too; seconds timestamps are scaled up
  function formatTime(ts, ref) {
    if (!ts) return ""
    var when = new Date(ts * (ts < 1e12 ? 1000 : 1))
    if (ref && Math.round((ref - when.getTime()) / 1000) < 60) return "now"
    var sameDay = when.toDateString() === (ref ? new Date(ref) : new Date()).toDateString()
    return Qt.formatDateTime(when, sameDay ? "HH:mm" : "dd.MM. HH:mm")
  }

  property string fontFamily: Style.font.family

  readonly property bool hovered: hoverTracker.hovered
  readonly property string timeLabel: formatTime(timestamp, now)

  signal closeRequested()
  signal cardClicked()
  // prefer notification image over app icon
  readonly property string smallIconSource: image.length > 0 ? image : Util.iconSource(appIcon)
  readonly property bool hasGlyph: glyph.length > 0
  readonly property bool compactGlyph: hasGlyph && smallIconSource.length === 0 && singleLineToast
  readonly property bool hasSmallIcon: smallIconSource.length > 0
  readonly property bool summaryStartsWithGlyph: NotificationLogic.summaryStartsWithGlyph(summary)
  readonly property bool singleLineToast: sanitizedBody.length === 0
  readonly property bool collapseRedundantIcon: singleLineToast && !hasGlyph && summaryStartsWithGlyph
  readonly property string sanitizedBody: NotificationLogic.sanitizeBody(body, app, appIcon)
  readonly property string styledBody: NotificationLogic.styledBody(body, app, appIcon)

  readonly property color bodyColor: Qt.darker(Color.notifications.text, 1.15)
  // rows use a left accent bar instead of a border
  readonly property var cardBorderSpec: isRow
    ? Border.flat("transparent", 0)
    : Border.flat(urgency === 2 ? Color.urgent : Util.alpha(Color.notifications.border, 0.5), 1)

  implicitWidth: root.isRow ? Style.panelWidth.normal : Style.space(420)
  // border insets keep content off the bottom edge
  implicitHeight: mainColumn.implicitHeight + contentTopInset + contentBottomInset
  radius: isRow ? Style.cornerRadius : Style.space(8)
  color: isRow
    ? (hovered ? Style.hoverFill : "transparent")
    : Color.notifications.background
  Behavior on color { ColorAnimation { duration: 100 } }
  borderSpec: cardBorderSpec
  clip: true

  HoverHandler { id: hoverTracker }

  // critical row accent
  Rectangle {
    visible: root.isRow && root.urgency === 2
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(2)
    height: parent.height - Style.space(8)
    radius: width / 2
    color: Color.urgent
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
    anchors.topMargin: root.borderWidth
    anchors.leftMargin: root.borderWidth
    anchors.rightMargin: root.borderWidth
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(10)
      Layout.rightMargin: Style.space(10)
      Layout.topMargin: root.singleLineToast ? Style.space(6) : Style.space(8)
      Layout.bottomMargin: root.singleLineToast ? Style.space(6) : Style.space(8)
      spacing: root.collapseRedundantIcon ? 0 : (root.compactGlyph ? Style.space(8) : Style.space(10))

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
          color: Color.notifications.text
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
        color: Color.notifications.text
        font.family: Style.font.iconFamily
        font.pixelSize: Style.font.icon
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        Layout.rightMargin: Style.space(10)
        spacing: Style.space(2)

        Row {
          Layout.fillWidth: true
          spacing: Style.spacing.xs
          visible: root.app.length > 0 || root.timeLabel.length > 0

          readonly property bool showDot: root.app.length > 0 && root.timeLabel.length > 0
          // dot gets its own slot so both gaps match
          readonly property real dotSlotWidth: showDot ? dotText.implicitWidth + spacing : 0

          Caption {
            width: Math.min(implicitWidth, parent.width - timeText.implicitWidth - parent.dotSlotWidth - parent.spacing)
            text: root.app
            elide: Text.ElideRight
          }
          Caption {
            id: dotText
            visible: parent.showDot
            text: "·"
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
          color: Color.notifications.text
          font.pixelSize: Style.font.body
          font.bold: true
          wrapMode: Text.WordWrap
          elide: Text.ElideRight
          maximumLineCount: 2
        }

        Text {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(2)
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
      }
    }
  }

  Item {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: root.borderWidth + Style.space(3)
    anchors.rightMargin: root.borderWidth + Style.space(3)
    width: Style.space(18)
    height: Style.space(18)
    visible: opacity > 0
    opacity: root.hovered ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 100 } }

    Text {
      anchors.centerIn: parent
      text: "x"
      color: closeArea.containsMouse ? Color.notifications.text : Qt.darker(Color.notifications.text, 1.4)
      font.pixelSize: Math.round(Style.font.caption * 1.44)
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
    color: Color.notifications.text
    opacity: Style.emphasis.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  HudFrame { shown: !root.isRow }
  Scanlines { shown: !root.isRow }
}
