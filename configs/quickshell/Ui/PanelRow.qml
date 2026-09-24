import QtQuick
import qs.Commons

/*
 * ─────────────────────────────────────────────────────────────────────────────
 * PanelRow — the full-width clickable row inside a hover panel
 * ─────────────────────────────────────────────────────────────────────────────
 *
 * WHAT IT IS. One row of a panel list: an optional leading glyph, a label, an
 * optional right-aligned trailing value, a selected state, a hover state, and
 * a click. Every panel list in this shell is made of these.
 *
 *   PanelRow { label: "Wi-Fi"; on: root.wifiOn; onActivated: root.toggleWifi() }
 *   PanelRow { label: "Internet speed test"; glyph: "\u{f04c5}"; onActivated: ... }
 *   PanelRow { label: "Choose wallpaper…"; filled: true; centered: true; ... }
 *
 * WHY IT EXISTS. Thirteen rows across five widgets were hand-rolled from the
 * same Rectangle + Row + MouseArea, in three different idioms: Network's
 * in-file `Row_` (glyph left, state dot, selected fill), Display's and System's
 * one-off buttons (centred label on a resting fill, and only one of the two
 * lit up on hover), and AudioIO's and Media's list rows (●/○ prefix). Same
 * gesture, same place on screen, three answers to what it should look like —
 * and a fourth every time someone added one.
 *
 * SHAPE, not behaviour. A row does not know what activating it means; it emits
 * `activated()` and the panel decides. It holds no state of its own either:
 * `on` is driven by the caller, so a row cannot disagree with the thing it
 * describes.
 */
Rectangle {
  id: root

  // ─────────────────────────────────────────────────────────── API

  property string label: ""
  // Leading icon, drawn in the pinned icon family.
  property string glyph: ""
  // Right-aligned secondary text: a signal percentage, a device name, a value.
  property string trailing: ""

  // A TOGGLE row shows its state as a filled/hollow dot instead of an icon — a VPN that is on, an audio device that is current.
  property bool stateMarker: false

  // Selected/active.
  property bool on: false

  // A row that is a BUTTON rather than a list entry rests on a fill instead of on the card, so it reads as pressable with nothing selected.
  property bool filled: false
  // Centre the label instead of running it from the left edge.
  property bool centered: false

  property bool enabled: true

  signal activated()

  // ─────────────────────────────────────────────────────────── shape

  height: Style.row.list
  radius: Style.cornerRadius
  opacity: enabled ? 1 : Style.emphasis.disabled

  readonly property color _text: on ? Color.menu.selectedText : Color.menu.text

  color: on ? Color.menu.selectedBackground
    : mouse.containsMouse && enabled ? Style.hoverFill
    : filled ? Style.normalFill
    : "transparent"

  Behavior on color { ColorAnimation { duration: 100 } }

  Row {
    id: content
    anchors.left: root.centered ? undefined : parent.left
    anchors.leftMargin: root.centered ? 0 : Style.spacing.md
    anchors.horizontalCenter: root.centered ? parent.horizontalCenter : undefined
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.sm

    Text {
      id: glyphText
      anchors.verticalCenter: parent.verticalCenter
      visible: root.glyph !== ""
      textFormat: Text.PlainText
      text: root.glyph
      color: root._text
      font.family: Style.font.iconFamily
      font.pixelSize: Style.font.icon
    }

    Text {
      id: markerText
      anchors.verticalCenter: parent.verticalCenter
      visible: root.glyph === "" && root.stateMarker
      textFormat: Text.PlainText
      text: root.on ? "●" : "○"
      color: root._text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      // Capped to the row, so long labels (audio device names) elide instead of overflowing.
      width: Math.max(0, Math.min(implicitWidth, root.width - Style.spacing.md * 2
        - (glyphText.visible ? glyphText.implicitWidth + content.spacing : 0)
        - (markerText.visible ? markerText.implicitWidth + content.spacing : 0)
        - (trailingText.visible ? trailingText.implicitWidth + Style.spacing.sm : 0)))
      textFormat: Text.PlainText
      text: root.label
      color: root._text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }

  Text {
    id: trailingText
    visible: root.trailing !== ""
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.md
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.trailing
    color: Color.menu.text
    opacity: root.on ? 1 : Style.emphasis.faint
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
