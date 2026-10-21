pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "discord"

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string statePath:
    runtimeDir ? runtimeDir + "/quickshell-discord-voice.json" : ""

  readonly property int avatarSize: Style.space(22)
  readonly property int ringWidth: Math.max(1, Style.space(2))
  readonly property color avatarBacking: Util.alpha(Colors.menu.text, 0.12)

  property bool inVoice: false
  property string channelName: ""
  property string guildName: ""
  property bool selfMute: false
  property bool selfDeaf: false
  property var participants: []
  readonly property int avatarCountMax: 5

  readonly property int staleAfterMs: 50000
  property bool stale: false
  readonly property bool live: inVoice && !stale

  visible: live

  implicitWidth: trigger.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  Timer {
    id: staleTimer
    onTriggered: root.stale = true
  }

  function armStale(updatedAt) {
    staleTimer.stop()
    if (updatedAt <= 0) {
      stale = false
      return
    }
    var leftMs = staleAfterMs - (Date.now() - updatedAt)
    stale = leftMs <= 0
    if (stale) return
    staleTimer.interval = leftMs
    staleTimer.start()
  }

  readonly property int speakingCount: {
    var n = 0
    for (let i = 0; i < participants.length; i++)
      if (participants[i].speaking) n++
    return n
  }

  function apply(text) {
    var d
    try {
      d = JSON.parse(text || "{}")
    } catch (e) {
      root.inVoice = false
      return
    }
    root.inVoice = d.inVoice === true
    root.armStale(Number(d.updatedAt) || 0)
    if (!root.inVoice) {
      root.participants = []
      return
    }
    root.channelName = String(d.channel || "")
    root.guildName = String(d.guild || "")
    root.selfMute = d.selfMute === true
    root.selfDeaf = d.selfDeaf === true
    root.participants = Array.isArray(d.participants) ? d.participants : []
  }

  FileView {
    path: root.statePath
    watchChanges: root.statePath !== ""
    printErrors: false
    onLoaded: {
      root.apply(text())
      Util.rearmWatch(this)
    }
    onLoadFailed: root.inVoice = false
    onFileChanged: reload()
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
    spacing: Style.spacing.sm

    Repeater {
      model: root.participants

      delegate: Item {
        id: chip
        required property var modelData
        required property int index
        anchors.verticalCenter: parent.verticalCenter
        visible: index < root.avatarCountMax
        width: root.avatarSize
        height: root.avatarSize

        readonly property bool silenced:
          modelData.selfDeaf || modelData.deaf || modelData.selfMute || modelData.mute

        scale: modelData.speaking ? 1.14 : 1.0
        Behavior on scale { NumberAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }

        Rectangle {
          anchors.centerIn: parent
          width: parent.width + root.ringWidth * 2
          height: width
          radius: width / 2
          color: "transparent"
          antialiasing: true
          border.width: root.ringWidth
          border.color: chip.modelData.speaking && !parent.silenced
            ? Colors.semantic.speaking
            : Util.alpha(Colors.menu.text, parent.silenced ? 0.12 : 0.22)
          Behavior on border.color { ColorAnimation { duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }
          layer.enabled: Style.fx.glow > 0 && chip.modelData.speaking && !chip.silenced
          layer.effect: Glow { shadowColor: Colors.semantic.speaking }
        }

        ClippingRectangle {
          anchors.fill: parent
          radius: width / 2
          color: root.avatarBacking
          antialiasing: true

          Image {
            id: avatarImage
            anchors.fill: parent
            source: chip.modelData.avatar || ""
            sourceSize.width: Math.ceil(width * 2 * Screen.devicePixelRatio)
            sourceSize.height: Math.ceil(height * 2 * Screen.devicePixelRatio)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            mipmap: true
            visible: status === Image.Ready
            opacity: chip.silenced ? Style.emphasis.faint : 1
            Behavior on opacity { NumberAnimation { duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }
          }

          Text {
            anchors.centerIn: parent
            visible: !avatarImage.visible
            text: String(chip.modelData.name || "?").charAt(0).toUpperCase()
            color: Colors.menu.text
            opacity: Style.emphasis.dim
            font.family: Style.font.family
            font.pixelSize: Math.round(root.avatarSize * 0.5)
            font.bold: true
          }
        }

        Rectangle {
          visible: parent.silenced
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: -root.ringWidth
          anchors.bottomMargin: -root.ringWidth
          width: 2 * Math.round(root.avatarSize * 0.58 / 2)
          height: width
          radius: width / 2
          antialiasing: true
          color: Colors.background
          border.width: root.ringWidth
          border.color: Util.alpha(Colors.urgent, 0.55)

          OpticalGlyph {
            anchors.centerIn: parent
            text: (chip.modelData.selfDeaf || chip.modelData.deaf)
              ? "\u{f0581}"    // md-volume_off
              : "\u{f036d}"    // md-microphone_off
            color: Colors.urgent
            fontSize: Math.round(parent.width * 0.72)
          }
        }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.participants.length > root.avatarCountMax
      text: "+" + (root.participants.length - root.avatarCountMax)
      color: root.bar ? root.bar.barForeground : Colors.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      opacity: Style.emphasis.dim
    }
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: if (root.bar) root.bar.hoverOpen(root.moduleName)
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    title: "VOICE"
    implicitWidth: Style.panelWidth.narrow
    implicitHeight: content.implicitHeight + padding * 2 + titleInset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.sm

      Item {
        width: parent.width
        implicitHeight: Math.max(voiceHero.implicitHeight, voiceMeta.implicitHeight)
        height: implicitHeight
        Hero {
          id: voiceHero
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          value: String(root.participants.length)
          unit: "in call"
        }
        Column {
          id: voiceMeta
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * 0.56
          spacing: Style.spacing.xxs
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: root.guildName
              ? root.guildName + "  ::  " + root.channelName
              : (root.channelName || "Voice call")
            color: Colors.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            visible: root.speakingCount > 0
            text: root.speakingCount + " SPEAKING"
            color: Colors.semantic.speaking
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Style.labelTracking
          }
        }
      }

      PanelSeparator {}

      Row {
        width: parent.width
        spacing: Style.spacing.xs

        ActionButton {
          width: (parent.width - Style.spacing.xs * 2) / 3
          glyph: root.selfMute ? "\u{f036d}" : "\u{f036c}"
          label: root.selfMute ? "Unmute" : "Mute"
          danger: root.selfMute
          tint: root.selfMute ? Colors.urgent : Colors.menu.text
          onActivated: DiscordControl.send("toggleSelfMute")
        }
        ActionButton {
          width: (parent.width - Style.spacing.xs * 2) / 3
          glyph: root.selfDeaf ? "\u{f0581}" : "\u{f02cb}"
          label: root.selfDeaf ? "Undeafen" : "Deafen"
          danger: root.selfDeaf
          tint: root.selfDeaf ? Colors.urgent : Colors.menu.text
          onActivated: DiscordControl.send("toggleSelfDeaf")
        }
        ActionButton {
          width: (parent.width - Style.spacing.xs * 2) / 3
          glyph: "\u{f03f5}"   // md-phone_hangup
          label: "Leave"
          danger: true
          tint: Colors.urgent
          onActivated: {
            DiscordControl.send("disconnect")
            if (root.bar) root.bar.closePanel(root.moduleName)
          }
        }
      }

      PanelSeparator {}

      Repeater {
        model: root.participants
        delegate: Row {
          id: participant
          required property var modelData
          width: content.width
          spacing: Style.spacing.xs

          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(26)
            height: width

            ClippingRectangle {
              anchors.fill: parent
              anchors.margins: Style.space(2)
              radius: width / 2
              color: root.avatarBacking
              antialiasing: true

              Image {
                anchors.fill: parent
                source: participant.modelData.avatar || ""
                sourceSize.width: Math.ceil(width * 2 * Screen.devicePixelRatio)
                sourceSize.height: Math.ceil(height * 2 * Screen.devicePixelRatio)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                mipmap: true
              }
            }

            Rectangle {
              anchors.fill: parent
              radius: width / 2
              color: "transparent"
              antialiasing: true
              border.width: Math.max(1, Style.space(2))
              border.color: participant.modelData.speaking
                ? Colors.semantic.speaking : Util.alpha(Colors.menu.text, 0.18)
              Behavior on border.color { ColorAnimation { duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }
            }
          }

          Row {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(26) - Style.space(74) - parent.spacing * 2
            spacing: Style.spacing.xs
            Text {
              id: nameLabel
              width: Math.min(implicitWidth, parent.width - (youLabel.visible ? youLabel.implicitWidth + parent.spacing : 0))
              textFormat: Text.PlainText
              text: participant.modelData.name
              color: participant.modelData.speaking ? Colors.accent : Colors.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              layer.enabled: Style.fx.glow > 0 && participant.modelData.speaking
              layer.effect: Glow {}
            }
            Text {
              id: youLabel
              visible: !!participant.modelData.self
              anchors.baseline: nameLabel.baseline
              text: "you"
              color: Colors.menu.text
              opacity: Style.emphasis.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(74)
            layoutDirection: Qt.RightToLeft
            spacing: Style.spacing.xs

            Text {
              visible: participant.modelData.selfDeaf || participant.modelData.deaf
              text: "\u{f0581}"   // md-volume_off
              color: participant.modelData.deaf ? Colors.urgent : Util.alpha(Colors.urgent, 0.75)
              font.family: Style.font.iconFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              visible: participant.modelData.selfMute || participant.modelData.mute
              text: "\u{f036d}"   // md-microphone_off
              color: participant.modelData.mute ? Colors.urgent : Util.alpha(Colors.urgent, 0.75)
              font.family: Style.font.iconFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              visible: participant.modelData.video
              text: "\u{f0567}"   // md-video
              color: Colors.menu.text
              opacity: Style.emphasis.dim
              font.family: Style.font.iconFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              visible: participant.modelData.streaming
              text: "\u{f1483}"   // md-monitor_share
              color: Colors.menu.text
              opacity: Style.emphasis.dim
              font.family: Style.font.iconFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
