import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

PopupWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  // Same chrome as Ui/HoverPanel, deliberately.
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property color borderColor: Color.menu.border
  property var borderSpec: Border.surfaceSpec(borderColor, Color.menu.border, Math.max(1, Style.space(2)))
  property bool open: false
  property bool centerOnBar: false
  // Optional terminal-window title; empty renders no title bar (backward compatible).
  property string title: ""
  // "click" — uses HyprlandFocusGrab so clicking outside dismisses the popup.
  property string triggerMode: "click"

  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property var popupScreen: anchorWindow ? anchorWindow.screen : null
  readonly property bool containsMouse: cardHover.hovered
  readonly property real screenW: popupScreen ? popupScreen.width : 0
  readonly property real screenH: popupScreen ? popupScreen.height : 0
  readonly property real barW: anchorWindow ? anchorWindow.width : 0
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((bar && (bar.position === "left" || bar.position === "right")) ? barW : 0) - root.margin * 2)
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((bar && (bar.position === "top" || bar.position === "bottom")) ? barH : 0) - root.margin * 2)
    : 0
  readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0) maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0) maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  function cappedContentHeight(height) {
    var desired = Math.max(root.padding * 2, Number(height) || root.padding * 2)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    return Math.round(Math.min(desired, maxHeight))
  }

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  default property alias contentItem: contentHolder.children

  visible: open || card.opacity > 0
  color: "transparent"
  implicitWidth: contentWidth
  implicitHeight: contentHeight

  // Upstream's bar owns a popout coordinator (requestPopout/releasePopout/ activePopout) that keeps one click-popup open at a time.
  onOpenChanged: {
    if (!bar || typeof bar.requestPopout !== "function") return
    if (open) bar.requestPopout(coordinatorKey)
    else if (bar.activePopout === coordinatorKey && typeof bar.releasePopout === "function")
      bar.releasePopout(coordinatorKey)
  }

  // Outside-click dismissal via Hyprland's focus grab.
  HyprlandFocusGrab {
    active: root.open && root.triggerMode === "click"
    windows: root.anchorWindow ? [root, root.anchorWindow] : [root]
    onCleared: root.close()
  }

  anchor {
    id: popupAnchor
    window: anchorItem ? anchorItem.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      if (!root.anchorItem || !root.bar) return

      var target = root.anchorItem
      var popupWidth = root.implicitWidth
      var popupHeight = root.implicitHeight
      var localX = target.width / 2 - popupWidth / 2
      var localY = target.height + root.margin

      if (root.bar.position === "bottom") {
        localY = -popupHeight - root.margin
      } else if (root.bar.position === "left") {
        localX = target.width + root.margin
        localY = target.height / 2 - popupHeight / 2
      } else if (root.bar.position === "right") {
        localX = -popupWidth - root.margin
        localY = target.height / 2 - popupHeight / 2
      }

      var window = target.QsWindow.window
      if (!window) return

      if (root.centerOnBar) {
        var cx = 0;
        var cy = 0;
        if (root.bar.position === "top" || root.bar.position === "bottom") {
          cx = window.width / 2 - popupWidth / 2
          cy = root.bar.position === "bottom" ? -popupHeight - root.margin : window.height + root.margin
          cx = Math.max(root.margin, Math.min(cx, window.width - popupWidth - root.margin))
        } else {
          cx = root.bar.position === "left" ? window.width + root.margin : -popupWidth - root.margin
          cy = window.height / 2 - popupHeight / 2
          cy = Math.max(root.margin, Math.min(cy, window.height - popupHeight - root.margin))
        }

        popupAnchor.rect.x = Math.round(cx)
        popupAnchor.rect.y = Math.round(cy)
        return
      }

      var point = window.contentItem.mapFromItem(target, localX, localY)

      if (root.bar.position === "top" || root.bar.position === "bottom") {
        point.x = Math.max(root.margin, Math.min(point.x, window.width - popupWidth - root.margin))
      } else {
        point.y = Math.max(root.margin, Math.min(point.y, window.height - popupHeight - root.margin))
      }

      popupAnchor.rect.x = Math.round(point.x)
      popupAnchor.rect.y = Math.round(point.y)
    }
  }

  BorderSurface {
    id: card
    anchors.fill: parent
    color: Color.menu.background
    borderSpec: root.borderSpec
    padding: root.padding
    radius: Style.cornerRadius
    opacity: root.open ? 1.0 : 0

    Behavior on opacity {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    // Subtle fade-paired slide; both Behaviors fire only on the open/close state change, never continuously.
    transform: Translate {
      y: root.open ? 0 : ((root.bar && root.bar.position === "bottom") ? Style.space(6) : -Style.space(6))
      Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }

    Item {
      id: contentHolder
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
    }

    // Optional terminal-window title strip: `> TITLE _` with decorative chrome and a hard accent rule, additive overlay so empty-title cards are unchanged.
    Item {
      id: titleBar
      visible: root.title.length > 0
      z: 4
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.topMargin: card.contentTopInset
      anchors.leftMargin: card.contentLeftInset
      anchors.rightMargin: card.contentRightInset
      height: visible ? titleRow.implicitHeight + Style.spacing.xxs + titleRule.height : 0

      Row {
        id: titleRow
        anchors.top: parent.top
        anchors.left: parent.left
        spacing: Style.spacing.xs

        Text {
          text: "> " + root.title
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          font.capitalization: Font.AllUppercase
          font.letterSpacing: Style.headerTracking
          layer.enabled: Style.fx.glow > 0
          layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Style.fx.glowColor
            shadowBlur: 1.0
            shadowVerticalOffset: 0
            shadowHorizontalOffset: 0
            blurMax: Style.fx.glowRadius
            autoPaddingEnabled: true
          }
        }

        // Blinking block caret.
        Text {
          text: "_"
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          SequentialAnimation on opacity {
            running: titleBar.visible
            loops: Animation.Infinite
            NumberAnimation { to: 0; duration: 500 }
            NumberAnimation { to: 1; duration: 500 }
          }
        }
      }

      // Decorative window chrome glyphs, non-interactive.
      Text {
        anchors.right: parent.right
        anchors.verticalCenter: titleRow.verticalCenter
        text: "[# - x]"
        color: Color.accent
        opacity: 0.7
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: Style.headerTracking
      }

      // Hard accent rule under the title.
      Rectangle {
        id: titleRule
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: titleRow.bottom
        anchors.topMargin: Style.spacing.xxs
        height: Math.max(1, Style.space(1))
        color: Util.alpha(Color.accent, 0.8)
      }
    }

    // Neon HUD corner brackets framing the popup.
    HudFrame { margin: -Style.space(3) }

    HoverHandler {
      id: cardHover
    }
  }
}
