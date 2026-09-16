import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell. The SPEC asks for "discord call: icons
// that move whose talking, mute, deafen indicators on the icons".
//
// WHERE THE DATA COMES FROM. Discord publishes none of this to the desktop:
// its local RPC socket has exactly the right events and gates all of them
// behind an OAuth scope that needs an app registered by hand on Discord's
// developer portal. So the source is a BetterDiscord plugin instead —
// configs/discord/plugins/QuickshellVoiceStatus.plugin.js — which reads the
// client's own stores and writes a small JSON file to XDG_RUNTIME_DIR. Its
// header carries the full reasoning. This file only ever reads that file.
//
// DEGRADES TO ABSENT. No Discord, no BetterDiscord injection, no call — the
// widget is simply not on the bar. There is no "Discord: not connected" state,
// because a permanent chip saying nothing is happening is worse than nothing.
//
// Glyphs verified BY NAME against the 0xProto Nerd Font cmap: md-microphone_off
// U+F036D, md-volume_off U+F0581, md-video U+F0567, md-monitor_share U+F1483.
BarWidget {
  id: root
  moduleName: "discord"

  // Written by the BetterDiscord plugin. XDG_RUNTIME_DIR is tmpfs, so this
  // cannot survive a reboot and report a call that ended days ago.
  //
  // NO /tmp FALLBACK, on both sides of the channel — the plugin dropped its
  // one for the same reason. XDG_RUNTIME_DIR is a 0700 per-user directory;
  // /tmp is world-writable, so falling back there would let any local process
  // both read who is in the call and, through the command file below, mute and
  // deafen the client. An unset XDG_RUNTIME_DIR means no session bus, in which
  // case this widget has nothing to read anyway.
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string statePath:
    runtimeDir ? runtimeDir + "/quickshell-discord-voice.json" : ""
  // The way back in. The BetterDiscord plugin polls this file and deletes it
  // as it reads — see its header for why the channel is a file and not a
  // socket (Discord's renderer `fs` shim has no watch, and no server).
  readonly property string commandPath:
    runtimeDir ? runtimeDir + "/quickshell-discord-cmd" : ""

  // Written with `printf`, not a FileView: FileView owns its path for reading
  // and re-arms a watch on it, which is the wrong shape for a write-only drop
  // box that the other side immediately unlinks.
  //
  // Write-then-rename, mirroring how the plugin publishes state back: the
  // plugin watches this path and reads it with a plain readFileSync, so a direct
  // `> path` can be read between the truncate and the write and hand it an
  // empty or half-written line. Both paths are in XDG_RUNTIME_DIR, one tmpfs,
  // so the rename is atomic and the reader only ever sees a complete command.
  function send(cmd) {
    if (!root.commandPath) return
    const target = Util.shellQuote(root.commandPath)
    const tmp = Util.shellQuote(root.commandPath + ".tmp")
    Quickshell.execDetached(["bash", "-c",
      "printf '%s\\n' " + Util.shellQuote(JSON.stringify({ cmd: cmd }))
        + " > " + tmp + " && mv -f " + tmp + " " + target])
  }

  // One place for the chip geometry: the ring is drawn outside the avatar, so
  // the widget's own width has to account for it and the badge hangs off the
  // corner by the same amount.
  readonly property int avatarSize: Style.space(22)
  readonly property int ringWidth: Math.max(1, Style.space(2))
  // The disc behind an avatar, shown while the image loads and behind the
  // initial when there is none. Not one of Style's state fills — it is a
  // placeholder surface, not a control — but it is one decision, so it is
  // written once rather than at each of the two draw sites.
  readonly property color avatarBacking: Util.alpha(Color.menu.text, 0.12)

  property bool inVoice: false
  property string channelName: ""
  property string guildName: ""
  property bool selfMute: false
  property bool selfDeaf: false
  property var participants: []
  property real updatedAt: 0

  // Discord can die without its plugin's stop() ever running, leaving the last
  // call frozen on disk. The plugin refreshes the timestamp every 15s while in
  // a call, so anything older than three missed beats is a corpse, not a quiet
  // conversation.
  property real nowMs: Date.now()
  readonly property bool stale: updatedAt > 0 && (nowMs - updatedAt) > 50000
  readonly property bool live: inVoice && !stale

  visible: live

  implicitWidth: trigger.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  // Only ticks while there is something to age out. A clock running for a
  // widget that is not on screen is the kind of cost that adds up across
  // twenty widgets.
  Timer {
    interval: 5000
    running: root.inVoice
    repeat: true
    onTriggered: root.nowMs = Date.now()
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
    root.updatedAt = Number(d.updatedAt) || 0
    root.nowMs = Date.now()
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
    id: stateFile
    // Empty path when there is no runtime directory — FileView simply never
    // loads, so `inVoice` stays false and the widget stays off the bar.
    path: root.statePath
    watchChanges: root.statePath !== ""
    printErrors: false
    onLoaded: {
      root.apply(text())
      // The plugin writes temp-file-then-rename, which replaces the inode the
      // watch is attached to. Without re-arming, the first call would show and
      // every later update would be silently dropped — the failure mode this
      // helper exists for.
      Util.rearmWatch(this)
    }
    onLoadFailed: root.inVoice = false
    onFileChanged: reload()
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: hoverArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  // The bar shows the faces, because "who is in this call and who is talking"
  // is the whole question. Everything else — channel name, per-person mute
  // detail — is panel material.
  Row {
    id: trigger
    anchors.centerIn: parent
    // Wider than the usual xs: each chip now carries a ring outside its own
    // bounds, so neighbours at xs spacing would have their rings touching.
    // Bumped md -> lg (+2px): chips at md read as touching once the ring
    // and badge are both drawn, reported as "icons should be 1-2px more
    // apart".
    spacing: Style.spacing.lg

    Repeater {
      // The whole list is the model, with the tail hidden, rather than a
      // `.slice(0, 5)`: slicing builds a new array on every update, and every
      // new array rebuilds all five delegates — including their avatars —
      // each time somebody starts or stops talking. A Row excludes invisible
      // children from layout, so hiding the tail costs no space either.
      model: root.participants

      delegate: Item {
        id: chip
        required property var modelData
        required property int index
        anchors.verticalCenter: parent.verticalCenter
        // Capped: a twelve-person call would otherwise push the centre section
        // off its own axis. The overflow count below says how many are hidden.
        visible: index < 5
        width: root.avatarSize
        height: root.avatarSize

        readonly property bool silenced:
          modelData.selfDeaf || modelData.deaf || modelData.selfMute || modelData.mute

        // The "icons that move" from the SPEC. Scale rather than a ring alone:
        // at this size a highlight ring is a couple of pixels and reads as
        // noise, whereas a face growing is unmistakable in peripheral vision.
        scale: modelData.speaking ? 1.14 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

        // The ring lives OUTSIDE the clipped avatar, drawn as a border on a
        // slightly larger circle behind it. Drawing it on top of a clipped
        // Image put a hard 2px stroke on an already hard-clipped edge, which
        // is what made these read as pasted-on squares rather than chips.
        Rectangle {
          anchors.centerIn: parent
          width: parent.width + root.ringWidth * 2
          height: width
          radius: width / 2
          color: "transparent"
          antialiasing: true
          border.width: root.ringWidth
          // Discord's own speaking green — a convention people already read,
          // the same deliberate exception to the palette as the OBS record red.
          border.color: modelData.speaking && !parent.silenced
            ? Color.semantic.speaking
            : Util.alpha(Color.menu.text, parent.silenced ? 0.12 : 0.22)
          Behavior on border.color { ColorAnimation { duration: 140 } }
        }

        // ClippingRectangle, not Rectangle. QtQuick's `clip` is a rectangular
        // scissor test and ignores `radius` entirely, so a rounded Rectangle
        // with clip:true still clipped its Image to a SQUARE — which is what
        // made these look like pasted-on tiles with a ring around them rather
        // than round avatars. Quickshell ships this exact type for the job.
        ClippingRectangle {
          id: avatarFrame
          anchors.fill: parent
          radius: width / 2
          color: root.avatarBacking
          antialiasing: true

          Image {
            id: avatarImage
            anchors.fill: parent
            source: modelData.avatar || ""
            // Decode at twice the drawn size, not at it. Discord publishes
            // these at 64px; decoding straight to ~20 threw away most of the
            // pixels and left a blocky result, and mipmapping a 20px texture
            // has nothing to work with. Two-times plus mipmap gives a clean
            // downscale for a quarter of the 64px memory.
            sourceSize.width: Math.ceil(width * 2 * Screen.devicePixelRatio)
            sourceSize.height: Math.ceil(height * 2 * Screen.devicePixelRatio)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            mipmap: true
            visible: status === Image.Ready
            // `chip.silenced`, not `parent.parent.silenced`. ClippingRectangle
            // reparents its children into an internal contentItem, so the
            // parent chain from here no longer reaches the delegate — the
            // expression resolved to undefined and the dim silently never
            // applied. Addressing the delegate by id is immune to that.
            opacity: chip.silenced ? Style.emphasis.faint : 1
            Behavior on opacity { NumberAnimation { duration: 140 } }
          }

          // Not every avatar loads (offline, blocked CDN, a user with none);
          // the initial on a tinted disc is a real fallback rather than an
          // empty hole.
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

        // Deafened outranks muted: someone deafened is also muted, and two
        // badges on a 22px avatar is two illegible marks instead of one
        // legible one. The disc is opaque and ringed in the bar background so
        // the badge stays readable over any avatar under it.
        Rectangle {
          visible: parent.silenced
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: -root.ringWidth
          anchors.bottomMargin: -root.ringWidth
          width: Math.round(root.avatarSize * 0.58)
          height: width
          radius: width / 2
          antialiasing: true
          color: root.bar ? root.bar.background : Color.menu.background
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
      visible: root.participants.length > 5
      text: "+" + (root.participants.length - 5)
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
    implicitWidth: Style.panelWidth.narrow + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

      PanelSectionHeader { text: "VOICE · " + root.participants.length + " IN CALL" }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        readonly property string base: root.guildName
          ? root.guildName + "  ·  " + root.channelName
          : (root.channelName || "Voice call")
        text: base + (root.speakingCount > 0 ? "  ·  " + root.speakingCount + " speaking" : "")
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        opacity: Style.emphasis.dim
        elide: Text.ElideRight
      }

      // --- my own controls ---
      //
      // Mute, deafen and leave: single actions on Discord's media-engine and
      // channel-action modules, the things worth reaching for without switching windows.
      //
      // There is deliberately NO "go live" button. Probed this Discord build
      // for it: no `startStream`, no `openGoLiveModal`, no module carrying
      // both start/stop stream, and no Go Live control findable in the DOM.
      // Screen-sharing also needs a source picked, which is a modal of
      // Discord's own. A button that silently did nothing would be worse than
      // its absence.
      Row {
        width: parent.width
        spacing: Style.spacing.sm

        component Action: Rectangle {
          property string glyph: ""
          property string label: ""
          property bool on: false
          signal activated()
          height: Style.row.control
          radius: Style.cornerRadius
          color: on
            ? Util.alpha(Color.urgent, actionMouse.containsMouse ? 0.30 : 0.20)
            : (actionMouse.containsMouse ? Style.hoverFill : Style.normalFill)
          Behavior on color { ColorAnimation { duration: 100 } }

          Row {
            anchors.centerIn: parent
            spacing: Style.spacing.xs
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: parent.parent.glyph
              color: parent.parent.on ? Color.urgent : Color.menu.text
              font.family: Style.font.iconFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: parent.parent.label
              color: parent.parent.on ? Color.urgent : Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
          }
        }

        Action {
          width: (parent.width - Style.spacing.sm * 2) / 3
          // md-microphone_off / md-microphone
          glyph: root.selfMute ? "\u{f036d}" : "\u{f036c}"
          label: root.selfMute ? "Unmute" : "Mute"
          on: root.selfMute
          onActivated: root.send("toggleSelfMute")
        }
        Action {
          width: (parent.width - Style.spacing.sm * 2) / 3
          // md-volume_off / md-headphones
          glyph: root.selfDeaf ? "\u{f0581}" : "\u{f02cb}"
          label: root.selfDeaf ? "Undeafen" : "Deafen"
          on: root.selfDeaf
          onActivated: root.send("toggleSelfDeaf")
        }
        Action {
          width: (parent.width - Style.spacing.sm * 2) / 3
          glyph: "\u{f03f5}"   // md-phone_hangup
          label: "Leave"
          // Always in the urgent style: it ends the call.
          on: true
          onActivated: {
            root.send("disconnect")
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
          spacing: Style.spacing.sm

          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(26)
            height: width

            // Same reasoning as the bar chip: real rounded clipping, ring
            // drawn outside the clipped area, decode at 2x the drawn size.
            ClippingRectangle {
              id: panelAvatar
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
              Behavior on border.color { ColorAnimation { duration: 140 } }
            }
          }

          Row {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(26) - Style.space(74) - parent.spacing * 2
            spacing: Style.spacing.sm
            Text {
              id: nameLabel
              width: Math.min(implicitWidth, parent.width - (youLabel.visible ? youLabel.implicitWidth + parent.spacing : 0))
              textFormat: Text.PlainText
              text: modelData.name
              color: modelData.speaking ? Color.accent : Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
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

          // Every state gets its own glyph here, unlike the bar, where space
          // only allows the strongest one. A server mute is shown apart from a
          // self mute because only one of them is the person's own choice.
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
