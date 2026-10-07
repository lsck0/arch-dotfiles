import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "discord"

  // written by the betterdiscord plugin
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string statePath:
    runtimeDir ? runtimeDir + "/quickshell-discord-voice.json" : ""

  readonly property int avatarSize: Style.space(22)
  readonly property int ringWidth: Math.max(1, Style.space(2))
  readonly property color avatarBacking: Util.alpha(Color.menu.text, 0.12)

  property bool inVoice: false
  property string channelName: ""
  property string guildName: ""
  property bool selfMute: false
  property bool selfDeaf: false
  property var participants: []
  readonly property int avatarCountMax: 5

  // discord can die without the plugin clearing the file
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
    for (var i = 0; i < participants.length; i++)
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
      // rename replaces the watched inode
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
    // rings sit outside each chip
    spacing: Style.spacing.sm

    Repeater {
      // not sliced: a new array rebuilds every avatar
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
          border.color: modelData.speaking && !parent.silenced
            ? Color.semantic.speaking
            : Util.alpha(Color.menu.text, parent.silenced ? 0.12 : 0.22)
          Behavior on border.color { ColorAnimation { duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }
          layer.enabled: Style.fx.glow > 0 && modelData.speaking && !chip.silenced
          layer.effect: Glow { shadowColor: Color.semantic.speaking }
        }

        ClippingRectangle {
          anchors.fill: parent
          radius: width / 2
          color: root.avatarBacking
          antialiasing: true

          Image {
            id: avatarImage
            anchors.fill: parent
            source: modelData.avatar || ""
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
            text: String(modelData.name || "?").charAt(0).toUpperCase()
            color: Color.menu.text
            opacity: 0.8
            font.family: Style.font.family
            font.pixelSize: Math.round(root.avatarSize * 0.5)
            font.bold: true
          }
        }

        // one badge only: deafened outranks muted
        Rectangle {
          visible: parent.silenced
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: -root.ringWidth
          anchors.bottomMargin: -root.ringWidth
          // even, so the centre lands on a whole pixel
          width: 2 * Math.round(root.avatarSize * 0.58 / 2)
          height: width
          radius: width / 2
          antialiasing: true
          color: Color.background
          border.width: root.ringWidth
          border.color: Util.alpha(Color.urgent, 0.55)

          OpticalGlyph {
            anchors.centerIn: parent
            text: (modelData.selfDeaf || modelData.deaf)
              ? "\u{f0581}"    // md-volume_off
              : "\u{f036d}"    // md-microphone_off
            color: Color.urgent
            fontSize: Math.round(parent.width * 0.72)
          }
        }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.participants.length > root.avatarCountMax
      text: "+" + (root.participants.length - root.avatarCountMax)
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      opacity: Style.emphasis.dim
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
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            visible: root.speakingCount > 0
            text: root.speakingCount + " SPEAKING"
            color: Color.semantic.speaking
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Style.headerTracking * 0.4
          }
        }
      }

      PanelSeparator {}

      Row {
        width: parent.width
        spacing: Style.spacing.xs

        ActionButton {
          width: (parent.width - Style.spacing.xs * 2) / 3
          // md-microphone_off / md-microphone
          glyph: root.selfMute ? "\u{f036d}" : "\u{f036c}"
          label: root.selfMute ? "Unmute" : "Mute"
          danger: root.selfMute
          tint: root.selfMute ? Color.urgent : Color.menu.text
          onActivated: DiscordControl.send("toggleSelfMute")
        }
        ActionButton {
          width: (parent.width - Style.spacing.xs * 2) / 3
          // md-volume_off / md-headphones
          glyph: root.selfDeaf ? "\u{f0581}" : "\u{f02cb}"
          label: root.selfDeaf ? "Undeafen" : "Deafen"
          danger: root.selfDeaf
          tint: root.selfDeaf ? Color.urgent : Color.menu.text
          onActivated: DiscordControl.send("toggleSelfDeaf")
        }
        ActionButton {
          width: (parent.width - Style.spacing.xs * 2) / 3
          glyph: "\u{f03f5}"   // md-phone_hangup
          label: "Leave"
          danger: true
          tint: Color.urgent
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
                source: modelData.avatar || ""
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
              border.color: modelData.speaking
                ? Color.semantic.speaking : Util.alpha(Color.menu.text, 0.18)
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
              text: modelData.name
              color: modelData.speaking ? Color.accent : Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              layer.enabled: Style.fx.glow > 0 && modelData.speaking
              layer.effect: Glow {}
            }
            Text {
              id: youLabel
              visible: !!modelData.self
              anchors.baseline: nameLabel.baseline
              text: "you"
              color: Color.menu.text
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
              visible: modelData.selfDeaf || modelData.deaf
              text: "\u{f0581}"   // md-volume_off
              color: modelData.deaf ? Color.urgent : Util.alpha(Color.urgent, 0.75)
              font.family: Style.font.iconFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              visible: modelData.selfMute || modelData.mute
              text: "\u{f036d}"   // md-microphone_off
              color: modelData.mute ? Color.urgent : Util.alpha(Color.urgent, 0.75)
              font.family: Style.font.iconFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              visible: modelData.video
              text: "\u{f0567}"   // md-video
              color: Color.menu.text
              opacity: Style.emphasis.dim
              font.family: Style.font.iconFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              visible: modelData.streaming
              text: "\u{f1483}"   // md-monitor_share
              color: Color.menu.text
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
