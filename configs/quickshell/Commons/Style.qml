pragma Singleton
import QtQuick
import Quickshell.Io

// design tokens: geometry, states, type, spacing, bar grid
QtObject {
  id: root

  readonly property int baseSize: Theme.fontSize
  readonly property real scale: baseSize / 12.0

  function space(px) { return Math.max(0, Math.round(px * scale)) }
  function spaceReal(px) { return Math.max(0, px * scale) }

  readonly property int cornerRadius: Math.max(0, Math.round(2 * scale))
  property int gapsOut: 5

  readonly property QtObject fx: QtObject {
    readonly property real glow: Theme.glowStrength
    readonly property color glowColor: Color.accent
    readonly property int glowRadius: Math.max(2, Math.round(4 * root.scale))
    readonly property real scanlineOpacity: Theme.scanlineOpacity
    readonly property int scanlineSpacing: Math.max(2, Theme.scanlineSpacing)
    readonly property bool brackets: Theme.cornerBrackets
    readonly property int bracketLen: root.space(7)
    readonly property int bracketWidth: Math.max(1, Math.round(1.5 * root.scale))
    readonly property real flicker: Theme.crtFlicker
    readonly property real matrixRain: Theme.matrixRain
    function glowAlpha(mult) { return Math.min(1, root.fx.glow * (mult === undefined ? 1 : mult)) }
  }

  readonly property real normalFillAlpha: 0.04
  readonly property real hoverFillAlpha: 0.10
  readonly property real selectedFillAlpha: 0.22
  readonly property real pressedFillAlpha: 0.28
  readonly property real focusFillAlpha: 0.14
  readonly property real selectionFillAlpha: 0.35

  readonly property real normalBorderAlpha: 0.45
  readonly property real hoverBorderAlpha: 0.70
  readonly property real focusBorderAlpha: 0.85
  readonly property real selectedBorderAlpha: 1.0

  readonly property int normalBorderWidth: 1
  readonly property int hoverBorderWidth: 1
  readonly property int focusBorderWidth: 2
  readonly property int selectedBorderWidth: 2

  readonly property int shadowOffset: 0
  readonly property real shadowAlpha: 0.0

  function normalStateColor(foreground, accent) { return foreground || Color.foreground }
  function hoverStateColor(foreground, accent) { return foreground || Color.foreground }
  function selectedStateColor(foreground, accent) { return accent || Color.accent }
  function pressedStateColor(foreground, accent) { return accent || Color.accent }
  function focusStateColor(foreground, accent) { return accent || Color.accent }
  function selectionStateColor(foreground, accent) { return accent || Color.accent }

  function normalFillFor(foreground, accent) { return Util.alpha(normalStateColor(foreground, accent), normalFillAlpha) }
  function hoverFillFor(foreground, accent) { return Util.alpha(hoverStateColor(foreground, accent), hoverFillAlpha) }
  function selectedFillFor(foreground, accent) { return Util.alpha(selectedStateColor(foreground, accent), selectedFillAlpha) }
  function pressedFillFor(foreground, accent) { return Util.alpha(pressedStateColor(foreground, accent), pressedFillAlpha) }
  function focusFillFor(foreground, accent) { return Util.alpha(focusStateColor(foreground, accent), focusFillAlpha) }
  function selectionFillFor(foreground, accent) { return Util.alpha(selectionStateColor(foreground, accent), selectionFillAlpha) }

  function normalBorderFor(foreground, accent) { return Util.alpha(normalStateColor(foreground, accent), normalBorderAlpha) }
  function hoverBorderFor(foreground, accent) { return Util.alpha(hoverStateColor(foreground, accent), hoverBorderAlpha) }

  readonly property color normalFill: normalFillFor(Color.foreground, Color.accent)
  readonly property color hoverFill: hoverFillFor(Color.foreground, Color.accent)
  readonly property color selectedFill: selectedFillFor(Color.foreground, Color.accent)
  readonly property color pressedFill: pressedFillFor(Color.foreground, Color.accent)
  readonly property color normalBorderColor: normalBorderFor(Color.foreground, Color.accent)
  readonly property color hoverBorderColor: hoverBorderFor(Color.foreground, Color.accent)

  // focus > hover > normal
  function controlFill(focused, hot, foreground, accent) {
    if (focused) return focusFillFor(foreground || Color.foreground, accent || Color.accent)
    if (hot) return hoverFillFor(foreground || Color.foreground, accent || Color.accent)
    return normalFillFor(foreground || Color.foreground, accent || Color.accent)
  }

  readonly property QtObject row: QtObject {
    readonly property int list: root.space(32)
    readonly property int control: root.space(28)
  }

  readonly property QtObject panelWidth: QtObject {
    readonly property int narrow: root.space(320)
    readonly property int normal: root.space(360)
    readonly property int wide: root.space(460)
  }

  readonly property QtObject emphasis: QtObject {
    readonly property real strong: 1.0
    readonly property real dim: 0.7
    readonly property real faint: 0.45
    // below faint so off differs from quiet
    readonly property real disabled: 0.3
  }

  readonly property QtObject spacing: QtObject {
    // one physical pixel at any scale
    readonly property int hairline: 1
    readonly property int xxs: root.space(2)
    readonly property int xs: root.space(3)
    readonly property int sm: root.space(4)
    readonly property int md: root.space(6)
    readonly property int lg: root.space(8)
    readonly property int xl: root.space(10)
    readonly property int huge: root.space(18)

    readonly property int controlGap: root.space(8)
    readonly property int controlPaddingX: root.space(12)
    readonly property int controlPaddingY: root.space(8)
    readonly property int inputPaddingY: root.space(8)
    readonly property int controlHeight: root.space(32)
    readonly property int rowPaddingX: root.space(14)
    readonly property int panelPadding: root.space(22)
    readonly property int popupPadding: root.space(16)
  }

  // ui and icon families resolve separately
  readonly property string fontFamily: Theme.fontFamily
  property string resolvedFontFamily: Theme.fontFamily
  readonly property string iconFontFamily: "0xProto Nerd Font"
  property string resolvedIconFontFamily: "0xProto Nerd Font"

  readonly property QtObject font: QtObject {
    readonly property string family: root.resolvedFontFamily
    // glyphs must use this, never family
    readonly property string iconFamily: root.resolvedIconFontFamily

    readonly property int caption: Math.max(1, root.baseSize - 2)
    readonly property int bodySmall: caption
    readonly property int body: root.baseSize
    readonly property int subtitle: title
    readonly property int title: root.baseSize + 2
    readonly property int heading: root.baseSize + 4
    readonly property int display: root.baseSize * 2
    readonly property int displayLarge: display
    readonly property int icon: root.baseSize + 2
    readonly property int iconSmall: Math.max(1, root.baseSize - 1)
  }

  readonly property real headerTracking: 2.4 * scale
  readonly property real displayTracking: -0.5 * scale

  // fixed slots so bar items align on a grid
  readonly property QtObject bar: QtObject {
    readonly property int sizeHorizontal: root.space(30)
    readonly property int iconSlot: root.space(30)
    readonly property int iconCanvas: root.space(16)
    readonly property int iconFont: root.baseSize + 2
    readonly property int statusSlot: root.space(22)

    readonly property int itemPaddingX: Math.round((iconSlot - iconCanvas) / 2)
    readonly property int itemGap: root.space(2)
    readonly property int groupGap: root.space(10)
    readonly property int pillInset: root.space(4)
  }

  // mirrors hyprland general:gaps_out
  property Process gapsOutProc: Process {
    id: gapsOutProc
    command: ["hyprctl", "-j", "getoption", "general:gaps_out"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var json = JSON.parse(text || "{}")
          var parts = String(json.css || "").match(/-?\d+(?:\.\d+)?/g) || []
          var n = parts.length > 0 ? Number(parts[0]) : Number(json.int)
          if (isFinite(n) && n >= 0) root.gapsOut = Math.max(0, Math.round(n / 2))
        } catch (e) {
          // hyprland not up yet, keep previous
        }
      }
    }
  }

  property Process fcMatchIconProc: Process {
    command: ["fc-match", "-f", "%{family[0]}", root.iconFontFamily]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var name = String(text || "").trim()
        if (name.length === 0) return
        root.resolvedIconFontFamily = name
        if (name !== root.iconFontFamily)
          console.warn("Style: icon font '" + root.iconFontFamily
            + "' is not installed; fc-match resolved to '" + name
            + "'. Every glyph in the shell will be a substitution.")
      }
    }
  }

  property Process fcMatchUiProc: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var name = String(text || "").trim()
        if (name.length === 0) return
        root.resolvedFontFamily = name
        if (name !== root.fontFamily)
          console.warn("Style: UI font '" + root.fontFamily
            + "' is not installed; fc-match resolved to '" + name + "'.")
      }
    }
  }

  // restart explicitly, a bound command would not rerun
  function resolveUiFont() {
    fcMatchUiProc.running = false
    fcMatchUiProc.command = ["fc-match", "-f", "%{family[0]}", root.fontFamily]
    fcMatchUiProc.running = true
  }

  onFontFamilyChanged: resolveUiFont()

  Component.onCompleted: {
    gapsOutProc.running = true
    fcMatchIconProc.running = true
    resolveUiFont()
  }
}
