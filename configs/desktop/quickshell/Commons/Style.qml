pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "Palette.js" as Palette

QtObject {
  id: root

  readonly property int baseSize: Theme.fontSize
  readonly property real scale: baseSize / 12.0

  function space(px) { return Math.max(0, Math.round(px * scale)) }
  function spaceReal(px) { return Math.max(0, px * scale) }

  readonly property int cornerRadius: Palette.RADIUS_PX
  property int gapsOut: 5

  component FxTokens: QtObject {
    readonly property real glow: Power.saver ? 0 : Theme.glowStrength
    readonly property color glowColor: Colors.accent
    readonly property int glowRadius: Math.max(2, Math.round(4 * root.scale))
    readonly property real scanlineOpacity: Power.saver ? 0 : Theme.scanlineOpacity
    readonly property int scanlineSpacing: Math.max(2, Theme.scanlineSpacing)
    readonly property bool brackets: Theme.cornerBrackets
    readonly property int bracketLen: root.space(7)
    readonly property int bracketWidth: Math.max(1, Math.round(1.5 * root.scale))
    readonly property real flicker: Power.saver ? 0 : Theme.crtFlicker
    readonly property real matrixRain: Power.saver ? 0 : Theme.matrixRain
  }
  readonly property FxTokens fx: FxTokens {}

  readonly property real normalFillAlpha: 0.04
  readonly property real hoverFillAlpha: 0.10
  readonly property real selectedFillAlpha: 0.22
  readonly property real pressedFillAlpha: 0.28
  readonly property real focusFillAlpha: 0.14
  readonly property real selectionFillAlpha: 0.35
  readonly property real tintFillAlpha: 0.16

  readonly property real normalBorderAlpha: 0.45
  readonly property real hoverBorderAlpha: 0.70
  readonly property real focusBorderAlpha: 0.85
  readonly property real selectedBorderAlpha: 1.0

  readonly property int normalBorderWidth: Palette.BORDER_PX
  readonly property int hoverBorderWidth: Palette.BORDER_PX
  readonly property int focusBorderWidth: 2
  readonly property int selectedBorderWidth: 2

  function normalStateColor(foreground, accent) { return foreground || Colors.foreground }
  function hoverStateColor(foreground, accent) { return foreground || Colors.foreground }
  function selectedStateColor(foreground, accent) { return accent || Colors.accent }
  function pressedStateColor(foreground, accent) { return accent || Colors.accent }
  function focusStateColor(foreground, accent) { return accent || Colors.accent }
  function selectionStateColor(foreground, accent) { return accent || Colors.accent }

  function normalFillFor(foreground, accent) { return Util.alpha(normalStateColor(foreground, accent), normalFillAlpha) }
  function hoverFillFor(foreground, accent) { return Util.alpha(hoverStateColor(foreground, accent), hoverFillAlpha) }
  function selectedFillFor(foreground, accent) { return Util.alpha(selectedStateColor(foreground, accent), selectedFillAlpha) }
  function pressedFillFor(foreground, accent) { return Util.alpha(pressedStateColor(foreground, accent), pressedFillAlpha) }
  function focusFillFor(foreground, accent) { return Util.alpha(focusStateColor(foreground, accent), focusFillAlpha) }
  function selectionFillFor(foreground, accent) { return Util.alpha(selectionStateColor(foreground, accent), selectionFillAlpha) }

  function normalBorderFor(foreground, accent) { return Util.alpha(normalStateColor(foreground, accent), normalBorderAlpha) }
  function hoverBorderFor(foreground, accent) { return Util.alpha(hoverStateColor(foreground, accent), hoverBorderAlpha) }

  readonly property color normalFill: normalFillFor(Colors.foreground, Colors.accent)
  readonly property color hoverFill: hoverFillFor(Colors.foreground, Colors.accent)
  readonly property color selectedFill: selectedFillFor(Colors.foreground, Colors.accent)
  readonly property color pressedFill: pressedFillFor(Colors.foreground, Colors.accent)
  readonly property color normalBorderColor: normalBorderFor(Colors.foreground, Colors.accent)
  readonly property color hoverBorderColor: hoverBorderFor(Colors.foreground, Colors.accent)

  function controlFill(focused, hot, foreground, accent) {
    if (focused) return focusFillFor(foreground || Colors.foreground, accent || Colors.accent)
    if (hot) return hoverFillFor(foreground || Colors.foreground, accent || Colors.accent)
    return normalFillFor(foreground || Colors.foreground, accent || Colors.accent)
  }

  component RowTokens: QtObject {
    readonly property int list: root.space(32)
    readonly property int control: root.space(28)
  }
  readonly property RowTokens row: RowTokens {}

  component PanelWidthTokens: QtObject {
    readonly property int narrow: root.space(320) + root.shape.neck * 2
    readonly property int normal: root.space(360) + root.shape.neck * 2
    readonly property int wide: root.space(460) + root.shape.neck * 2
  }
  readonly property PanelWidthTokens panelWidth: PanelWidthTokens {}

  component EmphasisTokens: QtObject {
    readonly property real strong: 1.0
    readonly property real dim: 0.7
    readonly property real faint: 0.45
    readonly property real disabled: 0.3
  }
  readonly property EmphasisTokens emphasis: EmphasisTokens {}

  component SpacingTokens: QtObject {
    readonly property int hair: 1
    readonly property int xxs: root.space(2)
    readonly property int xs: root.space(4)
    readonly property int sm: root.space(8)
    readonly property int md: root.space(12)
    readonly property int lg: root.space(16)
    readonly property int xl: root.space(24)
    readonly property int xxl: root.space(32)

    readonly property int controlGap: sm
    readonly property int controlPaddingX: md
    readonly property int controlPaddingY: sm
    readonly property int inputPaddingY: sm
    readonly property int panelPadding: lg
  }
  readonly property SpacingTokens spacing: SpacingTokens {}

  component ShapeTokens: QtObject {
    readonly property int data: 0
    readonly property int surface: root.cornerRadius
    readonly property int chamfer: root.space(8)
    readonly property int neck: root.space(8)
  }
  readonly property ShapeTokens shape: ShapeTokens {}

  component SurfaceTokens: QtObject {
    readonly property int padding: root.spacing.lg
    readonly property int borderWidth: Palette.BORDER_PX
    readonly property real ruleAlpha: 0.85
  }
  readonly property SurfaceTokens surface: SurfaceTokens {}

  component TranslucencyTokens: QtObject {
    readonly property real saver: 0.96
    readonly property real bar: Power.saver ? saver : Palette.OPACITY_BAR
    readonly property real panel: Power.saver ? saver : Palette.OPACITY_SURFACE
    readonly property real overlay: Power.saver ? saver : 0.92
    readonly property real scrim: 0.55
  }
  readonly property TranslucencyTokens translucency: TranslucencyTokens {}

  component MotionTokens: QtObject {
    readonly property bool enabled: !Power.saver
    readonly property int snap: 0
    readonly property int fast: enabled ? 90 : 0
    readonly property int base: enabled ? 160 : 0
    readonly property int exit: Math.round(base * 0.75)
    readonly property int slow: enabled ? 240 : 0
    readonly property int ambient: enabled ? 600 : 0
    readonly property int boot: enabled ? 220 : 0
    readonly property real closeRate: 0.6
    readonly property real switchRate: 0.3
    readonly property int fastEasing: Easing.OutCubic
    readonly property int ambientEasing: Easing.InOutQuad
    readonly property var enter: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property var leave: [0.38, 0.04, 1, 0.07, 1, 1]
  }
  readonly property MotionTokens motion: MotionTokens {}

  readonly property string fontFamily: Theme.fontFamily
  property string resolvedFontFamily: Theme.fontFamily
  readonly property string iconFontFamily: "0xProto Nerd Font"
  property string resolvedIconFontFamily: "0xProto Nerd Font"

  component FontTokens: QtObject {
    readonly property string family: root.resolvedFontFamily
    readonly property string iconFamily: root.resolvedIconFontFamily

    readonly property int captionFloor: 11
    readonly property int caption: Math.max(captionFloor, root.baseSize - 1)
    readonly property int bodySmall: caption
    readonly property int body: root.baseSize
    readonly property int subtitle: title
    readonly property int title: root.baseSize + 2
    readonly property int heading: root.baseSize + 4
    readonly property int display: root.baseSize * 2
    readonly property int displayLarge: display
    readonly property int hero: Math.round(root.baseSize * 10 / 3)
    readonly property int icon: root.baseSize + 2
    readonly property int iconSmall: Math.max(1, root.baseSize - 1)
  }
  readonly property FontTokens font: FontTokens {}

  readonly property real headerTracking: 2.4 * scale
  readonly property real labelTracking: 0.96 * scale
  readonly property real displayTracking: -0.5 * scale
  readonly property string decor: "[- o x]"

  component BarTokens: QtObject {
    readonly property int sizeHorizontal: root.space(30)
    readonly property int iconSlot: root.space(28)
    readonly property int iconCanvas: root.space(16)
    readonly property int iconFont: root.baseSize + 2
    readonly property int statusSlot: root.space(22)

    readonly property int itemPaddingX: Math.round((iconSlot - iconCanvas) / 2)
    readonly property int itemGap: root.spacing.xxs
    readonly property int groupGap: root.spacing.md
    readonly property int pillInset: root.spacing.xs
  }
  readonly property BarTokens bar: BarTokens {}

  property Process gapsOutProc: Process {
    command: ["hyprctl", "-j", "getoption", "general:gaps_out"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const json = JSON.parse(text || "{}")
          const parts = String(json.css || "").match(/-?\d+(?:\.\d+)?/g) || []
          const n = parts.length > 0 ? Number(parts[0]) : Number(json.int)
          if (isFinite(n) && n >= 0) root.gapsOut = Math.max(0, Math.round(n / 2))
        } catch (e) {
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

  function resolveUiFont() {
    fcMatchUiProc.running = false
    fcMatchUiProc.command = ["fc-match", "-f", "%{family[0]}", root.fontFamily]
    fcMatchUiProc.running = true
  }

  onFontFamilyChanged: resolveUiFont()

  Component.onCompleted: {
    root.gapsOutProc.running = true
    fcMatchIconProc.running = true
    resolveUiFont()
  }
}
