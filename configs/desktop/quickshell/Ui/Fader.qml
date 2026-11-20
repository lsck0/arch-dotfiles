import QtQuick
import Quickshell.Widgets
import qs.Commons

// a glyph, a slider and its reading; the caller owns what the level is and applies moved, released and muteToggled
Item {
  id: root

  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 0.05
  property bool integer: false
  property bool muted: false
  // false: the glyph only names the level, it is no mute button
  property bool muteable: true
  property string readoutText: ""
  property string readoutWidest: muteable ? "MUTED" : "100%"
  property string glyph: "\u{f057e}"
  property string mutedGlyph: "\u{f075f}"
  // an app's own icon in place of the glyph
  property url iconSource: ""
  property string caption: ""
  property real captionWidth: Style.space(52)

  readonly property real glyphSize: Style.space(24)

  signal moved(real value)
  signal released(real value)
  signal muteToggled()

  implicitHeight: slider.implicitHeight
  opacity: enabled ? 1 : Style.emphasis.disabled

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
    visible: root.muteable
    anchors.left: captionLabel.right
    anchors.leftMargin: root.caption !== "" ? Style.spacing.xs : 0
    anchors.verticalCenter: parent.verticalCenter
    variant: "icon"
    focusable: true
    size: root.glyphSize
    iconText: root.iconSource.toString() !== "" ? "" : root.muted ? root.mutedGlyph : root.glyph
    foreground: root.muted ? Colors.urgent : Colors.menu.text
    tooltipText: root.muted ? "Unmute" : "Mute"
    onClicked: root.muteToggled()

    IconImage {
      visible: root.iconSource.toString() !== ""
      anchors.centerIn: parent
      implicitSize: Style.font.icon + Style.spacing.xs
      source: root.iconSource
      opacity: root.muted ? Style.emphasis.disabled : 1
    }
  }

  Label {
    visible: !root.muteable
    anchors.fill: muteGlyph
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    text: root.glyph
    color: Colors.menu.text
    icon: true
  }

  Slider {
    id: slider
    anchors.left: muteGlyph.right
    anchors.right: readout.left
    anchors.leftMargin: Style.spacing.sm
    anchors.rightMargin: Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    minimum: root.minimum
    maximum: root.maximum
    step: root.step
    integer: root.integer
    value: root.value
    fillColor: root.muted ? Colors.urgent : Colors.bar.text
    onMoved: function(v) { root.moved(v) }
    onReleased: function(v) { root.released(v) }
    onRightClicked: if (root.muteable) root.muteToggled()
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

    Label { id: readoutWidest; visible: false; caption: true; font.features: { "tnum": 1 }; text: root.readoutWidest }
  }
}
