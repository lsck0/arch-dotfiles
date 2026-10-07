import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

/**
 * OverlayCard: the one chrome for full-screen overlays: scrim, chamfered card, HudTitle, optional
 * prompt line, content, key hint footer, and the cold boot open/close (BootIn). The window stays
 * mapped until the close has played out, and takes the keyboard only while open.
 *
 * Properties:
 *   open         target state
 *   name         layer namespace suffix, "quickshell-" + name (blurred by hyprland_windowrules.lua)
 *   title        HudTitle text; suffix is its faint tail, e.g. "[12]"
 *   prompt       show the `> query_` line; query is its text, placeholder shows while it is empty
 *   hints        KeyHints pairs for the footer, [] hides it
 *   cardWidth    card size, capped to the output; chromeWidth/chromeHeight help size to content
 *   cardHeight
 *   scanlines    scanline overlay plus the one-shot boot flicker
 *   keyboard     take exclusive keyboard focus while open
 *
 * Signals:
 *   dismissed()  scrim clicked
 *
 * Content goes in the area between prompt and footer (contentWidth x contentHeight); list rows may
 * fade in with boot.rowOpacity(index).
 *
 * Usage:
 *   OverlayCard {
 *     open: root.opened; name: "clipboard"; title: "clipboard"; prompt: true; query: root.filterText
 *     hints: [["ESC", "close"], ["ENTER", "copy"]]
 *     onDismissed: root.close()
 *     ListView { anchors.fill: parent }
 *   }
 */
PanelWindow {
  id: root

  property bool open: false
  property string name: "overlay"
  property string title: ""
  property string suffix: ""
  property bool prompt: false
  property string query: ""
  property string placeholder: ""
  property var hints: []
  property real cardWidth: Style.space(560)
  property real cardHeight: Style.space(480)
  property bool scanlines: true
  property bool keyboard: true

  signal dismissed()

  default property alias content: body.data
  readonly property alias card: card
  readonly property alias boot: boot
  readonly property real contentWidth: body.width
  readonly property real contentHeight: body.height

  readonly property real inset: Style.surface.borderWidth + Style.surface.padding
  readonly property real promptHeight: Style.font.heading + Style.spacing.controlPaddingY * 2
  readonly property real chromeWidth: inset * 2
  readonly property real chromeHeight: inset * 2 + titleBar.implicitHeight + chrome.spacing
    + (root.prompt ? root.promptHeight + chrome.spacing : 0)
    + (root.hints.length > 0 ? footer.implicitHeight + chrome.spacing : 0)

  visible: open || boot.progress > 0
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "quickshell-" + root.name
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: root.open && root.keyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  BootIn {
    id: boot
    active: root.open
    title: root.title
    span: Math.min(card.width, card.height) / 2
  }

  Rectangle {
    anchors.fill: parent
    color: Color.scrim
    opacity: boot.progress
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.open
    onClicked: root.dismissed()
  }

  Item {
    id: card
    anchors.centerIn: parent
    width: Math.min(root.cardWidth, root.width - Style.gapsOut * 2)
    height: Math.min(root.cardHeight, root.height - Style.gapsOut * 2)
    opacity: boot.progress

    // swallow clicks so only the scrim dismisses
    MouseArea { anchors.fill: parent }

    DockShape {
      anchors.fill: parent
      fillColor: Color.overlayFill
    }

    Column {
      id: chrome
      x: root.inset
      y: root.inset
      width: card.width - root.inset * 2
      height: card.height - root.inset * 2
      spacing: Style.spacing.sm

      HudTitle {
        id: titleBar
        width: parent.width
        text: root.title
        suffix: root.suffix
        typed: boot.typed
        size: Style.font.title
        decor: true
        rule: true
        blinking: root.open
      }

      Item {
        id: promptLine
        visible: root.prompt
        width: parent.width
        height: root.promptHeight

        Row {
          id: promptRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm

          Text {
            id: promptGlyph
            textFormat: Text.PlainText
            text: ">"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            // hug the text so the caret follows it
            width: Math.min(implicitWidth, promptRow.width - promptGlyph.width - caret.width - promptRow.spacing * 2)
            text: root.query || root.placeholder
            color: Color.menu.text
            opacity: root.query ? 1 : Style.emphasis.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          BlinkCaret { id: caret; size: Style.font.heading; prompt: true; running: root.open && root.prompt }
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Style.spacing.xxs
          color: Util.alpha(Color.accent, Style.surface.ruleAlpha)
        }
      }

      Item {
        id: body
        width: parent.width
        height: Math.max(0, chrome.height - titleBar.height - chrome.spacing
          - (promptLine.visible ? promptLine.height + chrome.spacing : 0)
          - (footer.visible ? footer.height + chrome.spacing : 0))
      }

      KeyHints {
        id: footer
        visible: root.hints.length > 0
        hints: root.hints
        // lands last in the boot stagger
        opacity: boot.rowOpacity(boot.staggerCap)
      }
    }

    HudFrame { inset: boot.bracketInset }
    Scanlines { shown: root.scanlines; flicker: true }
  }
}
