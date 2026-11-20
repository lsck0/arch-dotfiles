import QtQuick
import qs.Commons

// a mute glyph, a slider and its reading; the caller owns what the level is and applies moved and muteToggled
Item {
  id: root

  property real volume: 0
  property bool muted: false
  property string readoutText: ""
  property string glyph: "\u{f057e}"
  property string mutedGlyph: "\u{f075f}"
  property string caption: ""
  property real captionWidth: Style.space(52)

  signal moved(real value)
  signal muteToggled()

  implicitHeight: slider.implicitHeight

  Label {
    id: captionLabel
    visible: root.caption !== ""
    width: visible ? root.captionWidth : 0
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: root.caption
    color: root.muted ? Colors.urgentText : Colors.textDim
    elide: Text.ElideRight
    caption: true
  }

  Button {
    id: muteGlyph
    anchors.left: captionLabel.right
    anchors.leftMargin: root.caption !== "" ? Style.spacing.xs : 0
    anchors.verticalCenter: parent.verticalCenter
    variant: "icon"
    focusable: true
    size: Style.space(24)
    iconText: root.muted ? root.mutedGlyph : root.glyph
    foreground: root.muted ? Colors.urgent : Colors.menu.text
    tooltipText: root.muted ? "Unmute" : "Mute"
    onClicked: root.muteToggled()
  }

  Slider {
    id: slider
    anchors.left: muteGlyph.right
    anchors.right: readout.left
    anchors.leftMargin: Style.spacing.sm
    anchors.rightMargin: Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    value: root.volume
    fillColor: root.muted ? Colors.urgent : Colors.bar.text
    onMoved: function(v) { root.moved(v) }
    onRightClicked: root.muteToggled()
  }

  Label {
    id: readout
    width: readoutWidest.implicitWidth
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignRight
    text: root.muted ? "MUTED" : root.readoutText
    color: root.muted ? Colors.urgentText : Colors.menu.text
    caption: true
    font.features: { "tnum": 1 }

    // the widest reading: a boost above 0 dB carries a sign as well, and + is no narrower than -
    Label { id: readoutWidest; visible: false; caption: true; text: "100% +00.0 dB" }
  }
}
