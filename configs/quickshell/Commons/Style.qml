pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Structural design tokens: geometry, interactive states, typography,
// spacing, and the bar grid. Colour lives in Color.qml; the user-facing
// knobs both read from live in Theme.qml.
//
// Same token *shape* as omarchy-shell's Style.qml (state-color engine,
// derived spacing/typography scale, bar grid) with upstream's shell.toml
// per-theme override layer removed — but unlike the earlier port, the values
// here are no longer frozen literals. Everything dimensional is derived from
// `Theme.fontSize`, so one number in theme.json rescales type, spacing, panel
// widths and the bar together instead of leaving the body text bigger inside
// a grid that stayed put.
QtObject {
  id: root

  // ---------------------------------------------------------- scale
  //
  // Every dimension in the shell is a multiple of this. 12px is the design
  // baseline, so at the default size `scale` is exactly 1 and each token
  // below evaluates to the number it was hand-tuned to — changing the base
  // size is the only thing that moves them.
  readonly property int baseSize: Theme.fontSize
  readonly property real scale: baseSize / 12.0

  // The rem-equivalent used by call sites for their own dimensions (panel
  // widths, card sizes, ad-hoc margins). It used to be `Math.round(px)` —
  // an identity function, so ~200 call sites were writing fixed pixels
  // through something that looked like a scaling helper. Now it is one.
  function space(px) { return Math.max(0, Math.round(px * scale)) }
  function spaceReal(px) { return Math.max(0, px * scale) }

  // ---------------------------------------------------------- geometry
  //
  // "Refined brutalist" (2026-09-04, second pass). History worth keeping:
  // the 09-03 overhaul was zero-radius/hard-slab brutalism, softened the
  // same day to radius 6 after two distinct complaints — "too stark/harsh"
  // AND "cramped". Those pull in different directions, so this pass answers
  // only the first: edges get harder and states get louder, while the
  // padding/control-size bump that fixed "cramped" is kept in full.
  //
  // The result reads structural rather than raw: a small radius that still
  // registers as a cut corner, borders with real weight, an offset shadow,
  // and hierarchy carried by type weight and letter-tracking instead of by
  // heavier chrome.
  //
  // Pinned, NOT read from Hyprland's decoration:rounding. Inheriting window
  // rounding made the shell's own surfaces a side effect of an unrelated
  // setting.
  readonly property int cornerRadius: Math.max(0, Math.round(3 * scale))
  property int gapsOut: 5

  // ---------------------------------------------------------- state tokens
  //
  // Shared interactive-state tokens for every reusable surface in the kit.
  //   normal   — idle control chrome
  //   hover    — mouse hover OR panel keyboard cursor
  //   selected — persistent chosen/current state
  //   pressed  — mouse down
  //   focus    — Qt activeFocus
  //
  // Each resolver takes explicit (foreground, accent) so a caller can point
  // a control at a non-default palette role — e.g. an urgent-tinted delete
  // button passes its urgent colour as `accent` — without a second copy of
  // the ladder.
  //
  // The resolvers used to be six functions with identical bodies, all
  // returning `foreground` and ignoring the `accent` argument entirely: dead
  // weight left over from when the shell.toml override layer picked the role
  // per theme. The proof they were wrong is that seven call sites bypassed
  // them for a `selectedAccentFill` token added specifically to get the
  // accent they could not ask for. Selected/pressed/focus now genuinely
  // resolve to the accent, which is also what makes those states read as
  // loud rather than as a slightly brighter grey.
  readonly property real normalFillAlpha: 0.04
  readonly property real hoverFillAlpha: 0.10
  readonly property real selectedFillAlpha: 0.22
  readonly property real pressedFillAlpha: 0.28
  readonly property real focusFillAlpha: 0.14
  readonly property real selectionFillAlpha: 0.35

  // Ascending with emphasis. The old ladder had hover (0.25) *fainter* than
  // normal (0.4), so hovering a bordered control made its outline recede —
  // backwards, and invisible in review because no state was ever loud enough
  // to notice.
  readonly property real normalBorderAlpha: 0.45
  readonly property real hoverBorderAlpha: 0.70
  readonly property real focusBorderAlpha: 0.85
  readonly property real selectedBorderAlpha: 1.0

  // Structural weight is where this look lives. Idle chrome stays hairline;
  // the states that mean something get a second pixel, which at a 3px radius
  // reads as a drawn edge rather than a glow.
  readonly property int normalBorderWidth: 1
  readonly property int hoverBorderWidth: 1
  readonly property int focusBorderWidth: 2
  readonly property int selectedBorderWidth: 2

  // Offset shadow: a solid rectangle behind each surface, pushed down-right.
  // Not a blur or a glow — the offset itself is the effect. Its colour is a
  // palette role (Color.shadow), so it stays coherent as the wallpaper
  // changes instead of being a fixed black that goes muddy over a warm
  // background.
  //
  // Disabled (offset 0): the shadow sat outside the 1px surface border, so
  // every panel/button read as having TWO parallel edges at its corners —
  // the crisp border plus the offset shadow's own edge. One clean border is
  // the more minimal look and kills the double-line at the corners outright.
  // (2026-09-07: the "refined brutalist" pass leaned on the offset shadow
  // for depth; the double-line it produced read as noisy, not structural.)
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

  // Composite helpers for the focus > hover > normal priority chain used by
  // every form control surface (TextField, Dropdown, Toggle, etc.). Saves
  // callers from re-writing the three-line ternary ladder per Rectangle.
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

  // ---------------------------------------------------------- spacing
  //
  // Margins, gaps, padding and the standard control/popup dimensions. The
  // literals are the values tuned at the default size; `space()` carries
  // them across a font-size change so a bigger base does not leave text
  // pressed against chrome that stayed put.
  //
  // The padding scale below is the one bumped on 2026-09-04 for the
  // "cramped" complaint. It is deliberately unchanged by the brutalist pass.
  readonly property QtObject spacing: QtObject {
    // Hairline is a rendering constant, not a measurement — it stays one
    // physical pixel at every scale.
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

  // ---------------------------------------------------------- typography
  //
  // TWO families, and the split is load-bearing:
  //
  //   font.family     — UI/body text. User-selectable via theme.json.
  //   font.iconFamily — every glyph in the shell. Pinned to a Nerd Font
  //                     forever; theme.json cannot reach it.
  //
  // Why the split exists: "monospace" (or any user pick) resolves through
  // fc-match to whatever the system has, which will not carry the Nerd Font
  // icon codepoints the bar draws. Qt's fallback chain then silently
  // substitutes some other installed font that happens to contain the
  // codepoint — rendering a *different* glyph, not a missing one, with no
  // QML error either way. One shared family property is why the font picker
  // could not ship before Phase 2b.
  //
  // Both properties expose the fc-match-RESOLVED family, never the requested
  // one. Previously `font.family` returned the request while
  // `font.iconFamily` returned the resolution, so picking an uninstalled
  // family made the bar (which read the resolved name) and every panel
  // (which read the requested one) disagree about what they were rendering
  // in. `requestedFamily` is kept for UI that needs to echo the choice back.
  //
  // NAMING NOTE, deviating from the roadmap: it prescribed `Style.font.ui` /
  // `Style.font.icon`, but `font.icon` is already an int *size* token with
  // many call sites. `family`/`iconFamily` avoids that collision.
  readonly property string fontFamily: Theme.fontFamily
  property string resolvedFontFamily: Theme.fontFamily
  readonly property string iconFontFamily: "0xProto Nerd Font"
  property string resolvedIconFontFamily: "0xProto Nerd Font"

  readonly property QtObject font: QtObject {
    readonly property string family: root.resolvedFontFamily
    readonly property string requestedFamily: root.fontFamily
    // Use this for anything that renders a glyph, never font.family.
    readonly property string iconFamily: root.resolvedIconFontFamily

    // Steps, not ratios. A geometric scale collapses at these sizes — so
    // the near-body steps are offsets from the base and only the display
    // sizes are multiplied. At the default base of 12 this reproduces the
    // hand-tuned scale exactly.
    //
    // CONSOLIDATED 2026-09-07 (was 8 steps, several 1px apart — read as
    // incoherent): bodySmall and subtitle were 11px and 13px, one pixel each
    // off the steps around them, and displayLarge was 28 vs display's 24.
    // Each created a barely-distinguishable size that panels mixed into the
    // same row, which is what made type feel "AI-generated" rather than
    // deliberate. They're now aliased to the nearest surviving step — the
    // token names stay so the ~200 call sites keep working, but only five
    // rendered sizes remain: caption, body, title, heading, display.
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

    // Weight tokens. This is where hierarchy comes from now: one family, one
    // size step or two, and the difference carried by weight. Named rather
    // than using Font.Bold inline so a proportional user font (which may
    // ship more weights than a mono one) has a single place to be tuned.
    readonly property int weightNormal: Font.Normal
    readonly property int weightMedium: Font.Medium
    readonly property int weightBold: Font.Bold
  }

  // Letter-spacing for uppercase section headers and other tracked-out
  // labels. Widened for the brutalist pass — tracking plus weight is what
  // separates a header from body text when everything shares one family.
  // Scales with the base size so the optical spacing holds.
  readonly property real headerTracking: 2.4 * scale
  // Display numerals (clock, big readouts) read tighter, not wider.
  readonly property real displayTracking: -0.5 * scale

  // ---------------------------------------------------------- bar grid
  //
  // Fixed-width slots so bar icons/status text align on a grid instead of
  // sizing to implicitWidth and drifting ragged as labels change length.
  // Derived from the base size: a larger font in a 30px bar clips, so the
  // bar has to grow with it. `exclusiveZone` follows automatically, which is
  // what keeps Hyprland's reserved area correct.
  readonly property QtObject bar: QtObject {
    readonly property int sizeHorizontal: root.space(30)
    readonly property int sizeVertical: root.space(30)
    readonly property int iconSlot: root.space(30)
    readonly property int iconCanvas: root.space(16)
    readonly property int iconFont: root.baseSize + 2
    readonly property int statusSlot: root.space(22)
  }

  // Mirrors hyprctl's general:gaps_out so panels can match the live Hyprland
  // config without hardcoding it twice. decoration:rounding used to be read
  // here too, into a `hyprlandRounding` property that nothing ever read —
  // dropped along with its process.
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

  // fc-match verification for the ICON family specifically. fc-match always
  // answers with *something*, so a reply that is not the requested family
  // means the Nerd Font is not installed and every glyph in the shell is
  // about to be a silent substitution. Warn loudly rather than let it pass.
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

  // Separate resolve for the UI family, so a bad user font choice degrades
  // the text only and cannot take the icons with it. Re-runs whenever
  // theme.json changes the family.
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
  //
  // As a binding it raced: both `command` and onFontFamilyChanged depend on
  // the same property, QML does not order a binding re-evaluation against a
  // change handler, and the handler won — so the process launched with the
  // PREVIOUS family and wrote that back as the resolved one. The symptom was
  // a font switch resolving to the font you just switched away from, plus a
  // bogus "not installed" warning naming the new family.
  //
  // The race was unreachable until now only because fontFamily used to be a
  // literal in this file that a sed rewrote between runs; making the font
  // live is what made an assign-then-run ordering necessary.
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
