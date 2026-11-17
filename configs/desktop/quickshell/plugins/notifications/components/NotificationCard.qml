pragma ComponentBehavior: Bound
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
  property string glyph: ""
  property int urgency: 1
  property double timestamp: 0

  property string variant: "toast"
  readonly property bool isRow: variant === "row"

  property int bodyLines: 3
  // the body is longer than bodyLines shows
  readonly property alias truncated: bodyText.truncated

  property double now: 0

  property var actions: []
  // a string (maybe empty) when the live notification takes an inline reply, null otherwise
  property var replyPlaceholder: null
  readonly property bool canReply: !isRow && replyPlaceholder !== null && replyPlaceholder !== undefined
  property bool replying: false
  property int groupCount: 1
  property int segmentsLeft: 0
  readonly property int gaugeSegments: 4

  function formatTime(ts, ref) {
    if (!ts) return ""
    var when = new Date(ts * (ts < 1e12 ? 1000 : 1))
    if (ref && Math.round((ref - when.getTime()) / 1000) < 60) return "NOW"
    var sameDay = when.toDateString() === (ref ? new Date(ref) : new Date()).toDateString()
    return Qt.formatDateTime(when, sameDay ? Util.timeFormat : Util.dayFormat + " " + Util.timeFormat)
  }

  readonly property bool hovered: hoverTracker.hovered
  readonly property string timeLabel: formatTime(timestamp, now)

  signal closeRequested()
  signal cardClicked()
  signal actionInvoked(string identifier)
  signal replyStarted()
  signal replyCancelled()
  signal replySent(string text)

  onReplyingChanged: if (replying) replyField.forceActiveFocus(); else replyField.focus = false

  function submitReply() {
    var text = replyField.text.trim()
    if (text.length > 0) root.replySent(text)
  }
  readonly property string smallIconSource: image.length > 0 ? image : Util.iconSource(appIcon)
  readonly property bool hasGlyph: glyph.length > 0
  readonly property bool compactGlyph: hasGlyph && smallIconSource.length === 0 && singleLineToast
  readonly property bool hasSmallIcon: smallIconSource.length > 0
  readonly property bool summaryStartsWithGlyph: NotificationLogic.summaryStartsWithGlyph(summary)
  readonly property bool singleLineToast: sanitizedBody.length === 0
  readonly property bool collapseRedundantIcon: singleLineToast && !hasGlyph && summaryStartsWithGlyph
  readonly property string sanitizedBody: NotificationLogic.sanitizeBody(body, app, appIcon)
  readonly property string styledBody: NotificationLogic.styledBody(body, app, appIcon)

  readonly property real edge: isRow ? 0 : Style.surface.borderWidth
  readonly property bool critical: urgency === NotificationLogic.URGENCY_CRITICAL
  // the panels' inset: a toast pads like a hover panel, a history row stays on the panel's own rhythm
  readonly property real padX: isRow ? Style.spacing.md : Style.surface.padding

  implicitWidth: root.isRow ? Style.panelWidth.normal : Style.space(420)
  implicitHeight: mainColumn.implicitHeight + edge * 2
  radius: Style.shape.data
  color: isRow && activeFocus ? Style.focusFill
    : isRow && hovered ? Style.hoverFill
    : "transparent"
  Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
  clip: true

  HoverHandler { id: hoverTracker }

  // a history row is in the panel's focus chain: Return opens it as a click does, Delete removes it as a right click
  activeFocusOnTab: root.isRow
  Keys.onReturnPressed: if (root.isRow) root.cardClicked()
  Keys.onEnterPressed: if (root.isRow) root.cardClicked()
  Keys.onDeletePressed: if (root.isRow) root.closeRequested()

  GlassCard {
    visible: !root.isRow
    anchors.fill: parent
    z: -1
  }

  // critical is an urgent mark on the left; a toast's sits inside its hairline, clear of the corner brackets
  Rectangle {
    visible: root.critical
    anchors.left: parent.left
    anchors.leftMargin: root.edge
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(2)
    height: parent.height - (root.isRow ? Style.space(8) : (root.edge + Style.fx.bracketLen + Style.spacing.xs) * 2)
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
      Layout.leftMargin: root.padX
      Layout.rightMargin: root.padX
      Layout.topMargin: root.isRow ? (root.singleLineToast ? Style.spacing.xs : Style.spacing.sm) : Style.spacing.md
      Layout.bottomMargin: root.isRow ? (root.singleLineToast ? Style.spacing.xs : Style.spacing.sm) : Style.spacing.md
      spacing: root.collapseRedundantIcon ? 0 : (root.compactGlyph ? Style.spacing.sm : Style.spacing.md)

      Item {
        id: smallIconSlot
        Layout.preferredWidth: visible ? (root.isRow ? Style.space(24) : Style.space(32)) : 0
        Layout.preferredHeight: visible ? (root.isRow ? Style.space(24) : Style.space(32)) : 0
        Layout.alignment: Qt.AlignTop
        visible: !root.collapseRedundantIcon && !root.compactGlyph && (root.hasSmallIcon || root.hasGlyph) && (root.hasGlyph || smallIconImage.status !== Image.Error)

        Image {
          id: smallIconImage
          anchors.fill: parent
          source: root.smallIconSource
          sourceSize.width: smallIconSlot.width * Screen.devicePixelRatio
          sourceSize.height: smallIconSlot.height * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          visible: !root.hasGlyph || smallIconImage.status === Image.Ready
        }

        Label {
          anchors.centerIn: parent
          visible: root.hasGlyph && smallIconImage.status !== Image.Ready
          text: root.glyph
          color: Colors.notifications.text
          icon: true
          font.pixelSize: Style.font.displayLarge
          layer.enabled: !root.isRow && Style.fx.glow > 0
          layer.effect: Glow {}
        }
      }

      Label {
        Layout.alignment: Qt.AlignVCenter
        visible: root.compactGlyph
        text: root.glyph
        color: Colors.notifications.text
        icon: true
        font.pixelSize: Style.font.icon
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        // a toast's text stops short of its close mark
        Layout.rightMargin: root.isRow ? Style.spacing.md : closeMark.width + Style.shape.chamfer - root.padX
        spacing: Style.spacing.xxs

        Row {
          Layout.fillWidth: true
          spacing: Style.spacing.xs
          visible: root.app.length > 0 || root.timeLabel.length > 0

          readonly property bool showDot: root.app.length > 0 && root.timeLabel.length > 0
          readonly property real dotSlotWidth: showDot ? dotText.implicitWidth + spacing : 0

          Caption {
            width: Math.min(implicitWidth, parent.width - timeText.implicitWidth - parent.dotSlotWidth - parent.spacing)
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

        Label {
          Layout.fillWidth: true
          visible: root.summary.length > 0
          text: NotificationLogic.joinHyphens(root.summary)
          color: Colors.notifications.text
          font.bold: true
          wrapMode: Text.WrapAtWordBoundaryOrAnywhere
          elide: Text.ElideRight
          maximumLineCount: 2
        }

        Label {
          id: bodyText
          Layout.fillWidth: true
          Layout.topMargin: Style.spacing.xxs
          visible: root.sanitizedBody.length > 0
          text: root.styledBody
          textFormat: Text.StyledText
          color: Colors.notifications.text
          linkColor: Colors.accentText
          // same https-only allowlist as a notification's default action
          onLinkActivated: function (link) {
            var argv = NotificationLogic.parseExecArgv(JSON.stringify(["xdg-open", link]))
            if (argv) Quickshell.execDetached(["uwsm-app", "--"].concat(argv))
          }
          wrapMode: Text.WrapAtWordBoundaryOrAnywhere
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
              variant: "chip"
              required property var modelData
              text: modelData.text.toUpperCase()
              onClicked: root.actionInvoked(modelData.id)
            }
          }
        }

        // the field takes the keyboard only once clicked into: a toast never steals focus on its own
        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.spacing.xs
          visible: root.canReply
          spacing: Style.spacing.xs

          TextField {
            id: replyField
            Layout.fillWidth: true
            verticalPadding: Style.spacing.xs
            font.pixelSize: Style.font.caption
            placeholderText: root.replyPlaceholder || "reply"
            onPressed: if (!root.replying) root.replyStarted()
            onAccepted: root.submitReply()
            Keys.onEscapePressed: {
              replyField.clear()
              root.replyCancelled()
            }
          }
          Button {
            variant: "chip"
            text: "SEND"
            enabled: replyField.text.trim().length > 0
            onClicked: root.submitReply()
          }
        }

        KeyHints {
          Layout.fillWidth: true
          Layout.topMargin: Style.spacing.xs
          visible: root.canReply && root.replying
          hints: [["ENTER", "send"], ["ESC", "close"]]
        }
      }
    }

    // one unbroken track that empties in quarter steps; dashes this close to the bottom stroke read as gaps in the
    // border
    Rectangle {
      id: gauge
      Layout.fillWidth: true
      Layout.leftMargin: root.padX
      Layout.rightMargin: root.padX
      Layout.bottomMargin: Style.spacing.md
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

  // always on a toast, where a plain click runs the default action instead; on hover in a history row
  Button {
    id: closeMark
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: root.edge + (root.isRow ? Style.spacing.xs : Style.spacing.sm)
    anchors.rightMargin: root.edge + Style.shape.chamfer
    variant: "icon"
    iconText: "\u{f00d}"
    foreground: hot ? Colors.notifications.text : Colors.textDim
    fontSize: Style.font.caption
    visible: opacity > 0
    opacity: root.hovered || !root.isRow ? 1 : 0
    onClicked: root.closeRequested()

    Behavior on opacity { NumberAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
  }

  component Caption: Label {
    dim: true
    caption: true
    font.letterSpacing: Style.labelTracking
  }

}
