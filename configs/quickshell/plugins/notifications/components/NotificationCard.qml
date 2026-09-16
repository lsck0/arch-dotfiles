// Notification card. Pure presentational -- no service, Notification, or
// ListModel references. The popup container drives lifetime.
//
// Verbatim from omarchy-shell except: Border.surfaceSpec("notifications",
// "border", ...) -> Border.flat(...) -- this repo's Border.qml has no
// per-surface/per-theme override resolution layer (see Border.qml's own
// header), so a spec is just the color/width the caller passes, same
// adaptation as Clipboard.qml/ConfirmDialog.qml already made.

import QtQuick
import QtQuick.Layouts
import Quickshell
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
  // Nerd Font glyph rendered in the icon slot when no real icon is set.
  property string glyph: ""
  // NotificationUrgency: Low=0, Normal=1, Critical=2 (upstream).
  property int urgency: 1
  property double timestamp: 0
  property int cornerRadius: 0

  // "toast"  — a free-floating popup over the desktop. It needs its own edges,
  //            so it keeps the border and the opaque card background.
  // "row"    — an entry in the history list inside a panel that ALREADY has
  //            edges. Four bordered cards stacked inside one bordered card is
  //            what made the list read as a pile of boxes rather than a list;
  //            nothing else in this shell outlines its list rows.
  property string variant: "toast"
  readonly property bool isRow: variant === "row"

  // How many lines of body to show before eliding. The clamp exists so a long
  // list stays scannable — every row roughly the same height — which is a
  // reason that disappears when there is only one row to look at. The panel
  // decides, because only it knows how many rows there are.
  property int bodyLines: 3

  // Wall-clock reference for the relative timestamp. Passed in rather than
  // read here so a list of thirty rows ticks from one timer instead of thirty.
  property double now: 0

  // A clock time, with the day added once it is no longer today.
  //
  // I had this as a relative age ("4d") on the argument that staleness is the
  // question being asked. It is the wrong call for a history you scroll: "2m"
  // and "3m" beside each other tell you the order you already knew, whereas
  // 12:58 tells you the notification arrived during the meeting. Relative time
  // is kept only for the very recent, where a clock reading is noise.
  function formatTime(ts, ref) {
    if (!ts) return ""
    var ms = ts * (ts < 1e12 ? 1000 : 1)
    var when = new Date(ms)
    if (ref) {
      var secs = Math.max(0, Math.round((ref - ms) / 1000))
      if (secs < 60) return "now"
    }
    var today = ref ? new Date(ref) : new Date()
    var sameDay = when.getFullYear() === today.getFullYear()
      && when.getMonth() === today.getMonth()
      && when.getDate() === today.getDate()
    return sameDay ? Qt.formatDateTime(when, "HH:mm")
                   : Qt.formatDateTime(when, "dd.MM. HH:mm")
  }

  // The card's text family. Defaults to the theme font; exposed so a caller
  // can override it per card. Both body Texts read it, which they did not
  // before — this property was declared and then ignored while they used a
  // hardcoded family.
  property string fontFamily: Style.font.family

  readonly property bool hovered: hoverTracker.hovered
  readonly property string timeLabel: formatTime(timestamp, now)

  signal closeRequested()
  signal cardClicked()
  // Prefer per-notification media/avatar data, then fall back to the app icon.
  readonly property string smallIconSource: image.length > 0 ? image : iconSource(appIcon)
  readonly property bool hasGlyph: glyph.length > 0
  readonly property bool compactGlyph: NotificationLogic.shouldRenderCompactGlyph(glyph, smallIconSource, singleLineToast)
  readonly property bool hasSmallIcon: smallIconSource.length > 0
  readonly property bool summaryStartsWithGlyph: NotificationLogic.summaryStartsWithGlyph(summary)
  readonly property bool singleLineToast: sanitizedBody.length === 0
  readonly property bool collapseRedundantIcon: singleLineToast && !hasGlyph && summaryStartsWithGlyph
  readonly property string sanitizedBody: sanitizeBody(body)
  readonly property string styledBody: NotificationLogic.styledBody(body, app, appIcon)

  readonly property color dimColor: Qt.darker(Color.notifications.text, 1.4)
  readonly property color bodyColor: Qt.darker(Color.notifications.text, 1.15)
  readonly property color accentColor: urgency === 2 ? Color.urgent : (urgency === 0 ? dimColor : Color.notifications.countdown)
  // A row draws no outline at all; a critical one keeps a left-edge accent
  // instead, which is the only urgency cue it still needs inside a panel.
  readonly property var cardBorderSpec: isRow
    ? Border.flat("transparent", 0)
    : Border.flat(urgency === 2 ? Color.urgent : Util.alpha(Color.notifications.border, 0.5), 1)

  function sanitizeBody(s) {
    return NotificationLogic.sanitizeBody(s, app, appIcon)
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  implicitWidth: Style.panelWidth.normal
  // Add vertical border insets so mainColumn (inset by border on top/left/right)
  // doesn't push content under the bottom edge.
  implicitHeight: mainColumn.implicitHeight + borderTop + borderBottom
  radius: isRow ? Style.cornerRadius : Style.space(8)
  // A row is transparent at rest and lights up on hover, exactly like every
  // other selectable row in the shell (audio devices, Wi-Fi networks, tunnels).
  color: isRow
    ? (hovered ? Style.hoverFill : "transparent")
    : Color.notifications.background
  Behavior on color { ColorAnimation { duration: 100 } }
  borderSpec: cardBorderSpec
  clip: true

  HoverHandler { id: hoverTracker }

  // Urgency rule for a row, standing in for the border a toast gets.
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
    anchors.topMargin: root.borderTop
    anchors.leftMargin: root.borderLeft
    anchors.rightMargin: root.borderRight
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
        // Smaller in a list: at 32 the avatar dominated a two-line row and
        // left the text looking like a caption hung off a picture.
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

        // WHO AND WHEN. Both were properties on this card and neither was ever
        // drawn — so two notifications from different apps were indistinguishable
        // in a toast, and the history could not say whether something arrived a
        // minute or a week ago. It is the first line because it is the context
        // the summary is read against.
        Row {
          Layout.fillWidth: true
          spacing: Style.spacing.xs
          visible: root.app.length > 0 || root.timeLabel.length > 0

          readonly property bool showDot: root.app.length > 0 && root.timeLabel.length > 0
          // Row's own `spacing` sat between "App" and the dot, but the gap
          // after the dot was two literal space glyphs baked into timeText's
          // string — a different, font-dependent width, so the two gaps
          // either side of "·" never matched. Both are the same Row spacing
          // now: the dot is its own Text instead of a prefix on timeText.
          readonly property real dotSlotWidth: showDot ? dotText.implicitWidth + spacing : 0

          Text {
            textFormat: Text.PlainText
            width: Math.min(implicitWidth, parent.width - timeText.implicitWidth - parent.dotSlotWidth - parent.spacing)
            text: root.app
            elide: Text.ElideRight
            color: Color.notifications.text
            opacity: Style.emphasis.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            id: dotText
            textFormat: Text.PlainText
            visible: parent.showDot
            // Middot, not a wider gap: "App 6  1m" still reads as one phrase
            // whatever the spacing, because both halves are the same weight and
            // colour. A separator says they are two facts.
            text: "·"
            color: Color.notifications.text
            opacity: Style.emphasis.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            id: timeText
            textFormat: Text.PlainText
            text: root.timeLabel
            color: Color.notifications.text
            opacity: Style.emphasis.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: root.summary.length > 0
          text: root.summary
          // Was a hardcoded "Liberation Sans" (upstream carry, unexplained).
          // These two Texts were the only strings in the whole shell that
          // ignored the theme font, so choosing a family left every
          // notification still rendering in something else.
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

  // Hover-revealed close. Stacked after mainColumn so its MouseArea sits
  // above the full-card one and the click never reaches cardClicked.
  Item {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: root.borderTop + Style.space(3)
    anchors.rightMargin: root.borderRight + Style.space(3)
    width: Style.space(18)
    height: Style.space(18)
    visible: opacity > 0
    opacity: root.hovered ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 100 } }

    Text {
      anchors.centerIn: parent
      text: "✕"
      color: closeArea.containsMouse ? Color.notifications.text : root.dimColor
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
}
