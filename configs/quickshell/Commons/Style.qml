pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Structural design tokens: geometry, interactive states, typography, spacing, and the bar grid.
QtObject {
  id: root

  // ---------------------------------------------------------- scale Every dimension in the shell is a multiple of this.
  readonly property int baseSize: Theme.fontSize
  readonly property real scale: baseSize / 12.0

  // The rem-equivalent used by call sites for their own dimensions (panel widths, card sizes, ad-hoc margins).
  function space(px) { return Math.max(0, Math.round(px * scale)) }
  function spaceReal(px) { return Math.max(0, px * scale) }

  // ---------------------------------------------------------- geometry Sci-fi HUD: near-hard edges, framing carried by fx corner brackets.
  readonly property int cornerRadius: Math.max(0, Math.round(2 * scale))
  property int gapsOut: 5

  // ---------------------------------------------------------- hacker fx One place every component reads its neon glow / scanline / HUD framing from.
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
    // Convenience: an accent glow at a given intensity multiplier.
    function glowAlpha(mult) { return Math.min(1, root.fx.glow * (mult === undefined ? 1 : mult)) }
  }

  // ---------------------------------------------------------- state tokens Shared interactive-state tokens for every reusable surface in the kit.
  readonly property real normalFillAlpha: 0.04
  readonly property real hoverFillAlpha: 0.10
  readonly property real selectedFillAlpha: 0.22
  readonly property real pressedFillAlpha: 0.28
  readonly property real focusFillAlpha: 0.14
  readonly property real selectionFillAlpha: 0.35

  // Ascending with emphasis.
  readonly property real normalBorderAlpha: 0.45
  readonly property real hoverBorderAlpha: 0.70
  readonly property real focusBorderAlpha: 0.85
  readonly property real selectedBorderAlpha: 1.0

  // Structural weight is where this look lives.
  readonly property int normalBorderWidth: 1
  readonly property int hoverBorderWidth: 1
  readonly property int focusBorderWidth: 2
  readonly property int selectedBorderWidth: 2

  // Offset shadow: a solid rectangle behind each surface, pushed down-right.
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
  function selectedBorderFor(foreground, accent) { return Util.alpha(selectedStateColor(foreground, accent), selectedBorderAlpha) }
  function focusBorderFor(foreground, accent) { return Util.alpha(focusStateColor(foreground, accent), focusBorderAlpha) }

  // Convenience colors resolved against the foundational palette.
  readonly property color normalFill: normalFillFor(Color.foreground, Color.accent)
  readonly property color hoverFill: hoverFillFor(Color.foreground, Color.accent)
  readonly property color selectedFill: selectedFillFor(Color.foreground, Color.accent)
  readonly property color pressedFill: pressedFillFor(Color.foreground, Color.accent)
  readonly property color focusFillColor: focusFillFor(Color.foreground, Color.accent)
  readonly property color selectionFill: selectionFillFor(Color.foreground, Color.accent)
  readonly property color normalBorderColor: normalBorderFor(Color.foreground, Color.accent)
  readonly property color hoverBorderColor: hoverBorderFor(Color.foreground, Color.accent)
  readonly property color selectedBorderColor: selectedBorderFor(Color.foreground, Color.accent)
  readonly property color focusBorderColor: focusBorderFor(Color.foreground, Color.accent)

  // Composite helpers for the focus > hover > normal priority chain used by every form control surface (TextField, Dropdown, Toggle, etc.).
  function controlFill(focused, hot, foreground, accent) {
    if (focused) return focusFillFor(foreground || Color.foreground, accent || Color.accent)
    if (hot) return hoverFillFor(foreground || Color.foreground, accent || Color.accent)
    return normalFillFor(foreground || Color.foreground, accent || Color.accent)
  }

  function controlBorder(focused, hot, foreground, accent) {
    if (focused) return focusBorderFor(foreground || Color.foreground, accent || Color.accent)
    if (hot) return hoverBorderFor(foreground || Color.foreground, accent || Color.accent)
    return normalBorderFor(foreground || Color.foreground, accent || Color.accent)
  }

  function controlBorderWidth(focused, hot) {
    if (focused) return focusBorderWidth
    if (hot) return hoverBorderWidth
    return normalBorderWidth
  }

  // ---------------------------------------------------------- panel metrics Heights and widths for the two things panels are actually made of, because the shell had stopped agreeing with itself about either.
  readonly property QtObject row: QtObject {
    // A selectable entry in a panel list: an audio device, a Wi-Fi network, a toggle line, a media player.
    readonly property int list: root.space(32)
    // A pressable chip or button sitting inside a panel.
    readonly property int control: root.space(28)
  }

  // Hover-panel widths were 300 / 320 / 340 / 360 / 380 / 460 — six widths for cards that hang off the same bar and are read the same way.
  readonly property QtObject panelWidth: QtObject {
    readonly property int narrow: root.space(320)
    readonly property int normal: root.space(360)
    // Only for a panel that genuinely carries more: the weather panel's three data tiers plus the radar.
    readonly property int wide: root.space(460)
  }

  // ---------------------------------------------------------- emphasis Four levels, because the UI only ever meant four.
  readonly property QtObject emphasis: QtObject {
    // Primary content.
    readonly property real strong: 1.0
    // Secondary: a value beside its label, a subtitle.
    readonly property real dim: 0.7
    // Tertiary: captions, units, provenance, "nothing here" placeholders.
    readonly property real faint: 0.45
    // Unavailable or not applicable — deliberately below faint so "off" is distinguishable from "quiet".
    readonly property real disabled: 0.3
  }

  // ---------------------------------------------------------- spacing Margins, gaps, padding and the standard control/popup dimensions.
  readonly property QtObject spacing: QtObject {
    // Hairline is a rendering constant, not a measurement — it stays one physical pixel at every scale.
    readonly property int hairline: 1
    readonly property int xxs: root.space(2)
    readonly property int xs: root.space(3)
    readonly property int sm: root.space(4)
    readonly property int md: root.space(6)
    readonly property int lg: root.space(8)
    readonly property int xl: root.space(10)
    readonly property int xxl: root.space(12)
    readonly property int xxxl: root.space(14)
    readonly property int huge: root.space(18)

    readonly property int controlGap: root.space(8)
    readonly property int controlPaddingX: root.space(12)
    readonly property int controlPaddingY: root.space(8)
    readonly property int inputPaddingY: root.space(8)
    readonly property int controlHeight: root.space(32)
    readonly property int popupRowHeight: root.space(32)
    readonly property int dropdownWidth: root.space(240)
    readonly property int searchableDropdownWidth: root.space(260)
    readonly property int numberFieldWidth: root.space(120)
    readonly property int searchablePopupMinHeight: root.space(220)
    readonly property int rowGap: root.space(10)
    readonly property int rowPaddingX: root.space(14)
    readonly property int labelGap: root.space(5)
    readonly property int panelGap: root.space(16)
    readonly property int panelPadding: root.space(22)
    readonly property int popupPadding: root.space(16)
  }

  // ---------------------------------------------------------- typography TWO families, and the split is load-bearing: font.family     — UI/body text.
  readonly property string fontFamily: Theme.fontFamily
  property string resolvedFontFamily: Theme.fontFamily
  readonly property string iconFontFamily: "0xProto Nerd Font"
  property string resolvedIconFontFamily: "0xProto Nerd Font"

  readonly property QtObject font: QtObject {
    readonly property string family: root.resolvedFontFamily
    readonly property string requestedFamily: root.fontFamily
    // Use this for anything that renders a glyph, never font.family.
    readonly property string iconFamily: root.resolvedIconFontFamily

    // Steps, not ratios.
    readonly property int caption: Math.max(1, root.baseSize - 2)
    readonly property int bodySmall: caption  // was base-1; now one small step
    readonly property int body: root.baseSize
    readonly property int subtitle: title    // was base+1; merged into title
    readonly property int title: root.baseSize + 2
    readonly property int heading: root.baseSize + 4
    readonly property int display: root.baseSize * 2
    readonly property int displayLarge: display  // was ~base*2.33; merged into display
    readonly property int icon: root.baseSize + 2
    readonly property int iconSmall: Math.max(1, root.baseSize - 1)
    readonly property int iconLarge: root.baseSize + 6

    // Weight tokens.
    readonly property int weightNormal: Font.Normal
    readonly property int weightMedium: Font.Medium
    readonly property int weightBold: Font.Bold
  }

  // Letter-spacing for uppercase section headers and other tracked-out labels.
  readonly property real headerTracking: 2.4 * scale
  // Display numerals (clock, big readouts) read tighter, not wider.
  readonly property real displayTracking: -0.5 * scale

  // ---------------------------------------------------------- bar grid Fixed-width slots so bar icons/status text align on a grid instead of sizing to implicitWidth and drifting ragged as labels change length.
  readonly property QtObject bar: QtObject {
    readonly property int sizeHorizontal: root.space(30)
    readonly property int sizeVertical: root.space(30)
    readonly property int iconSlot: root.space(30)
    readonly property int iconCanvas: root.space(16)
    readonly property int iconFont: root.baseSize + 2
    readonly property int statusSlot: root.space(22)

    // ---- one rhythm for the whole bar ------------------------------------ These three exist because the spacing used to come from two unrelated places and did not agree.
    readonly property int itemPaddingX: Math.round((iconSlot - iconCanvas) / 2)
    readonly property int itemGap: root.space(2)
    // Around a separator, so a group boundary reads as clearly wider than the gap between two widgets inside a group.
    readonly property int groupGap: root.space(10)
    // Keeps a filled pill (the focused workspace) off the bar's top and bottom edges.
    readonly property int pillInset: root.space(4)
  }

  // Mirrors hyprctl's general:gaps_out so panels can match the live Hyprland config without hardcoding it twice.
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
          // hyprctl missing / Hyprland not running yet — leave previous value.
        }
      }
    }
  }

  // fc-match verification for the ICON family specifically.
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

  // Separate resolve for the UI family, so a bad user font choice degrades the text only and cannot take the icons with it.
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

  // `command` is assigned here rather than bound to root.fontFamily.
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
