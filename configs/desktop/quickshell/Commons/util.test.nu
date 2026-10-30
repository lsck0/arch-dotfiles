#!/usr/bin/env -S nu --no-config-file
# Util.qml's text helpers and Palette.js's derived palette under qmltestrunner, Util alone in a module so the service
# singletons stay unloaded

const UTIL = path self | path dirname | path join Util.qml
const PALETTE = path self | path dirname | path join Palette.js
const RUNNER = "/usr/lib/qt6/bin/qmltestrunner"
const TEST = '
import QtQuick
import QtTest
import utiltest
import "utiltest/Palette.js" as Palette

TestCase {
  name: "util"

  function test_word_delete() {
    compare(Util.wordDelete("hello world"), "hello ")
    compare(Util.wordDelete("hello world  "), "hello ")
    compare(Util.wordDelete("foo.bar"), "foo.")
    compare(Util.wordDelete("foo..."), "foo")
    compare(Util.wordDelete("+tag"), "+")
    compare(Util.wordDelete(""), "")
    compare(Util.wordStart("ab cd", 2), 0)
    verify(Util.isWordDelete(Qt.Key_W, Qt.ControlModifier))
    verify(Util.isWordDelete(Qt.Key_Backspace, Qt.ControlModifier))
    verify(!Util.isWordDelete(Qt.Key_W, Qt.NoModifier))
  }

  function test_completion() {
    compare(Util.completion("wo", ["work", "workout", "home"]), "work")
    compare(Util.completion("ho", ["work", "home"]), "home")
    compare(Util.completion("x", ["work"]), "x")
    compare(Util.completion("", []), "")
  }

  readonly property var knobs: ({
    backgroundValueMin: Palette.BG_VALUE_MIN, backgroundValueMax: Palette.BG_VALUE_MAX,
    lightLuminance: Palette.LIGHT_LUMINANCE, foregroundContrast: 7, accentMinSaturation: 0.7, accentMinValue: 0.62,
    accentContrast: 3, urgentMinSaturation: 0.55, urgentMinValue: 0.55, urgentContrast: 3, mutedContrast: 1.9,
    phosphorBias: 0, accent2Contrast: 3, urgentMinApart: 40, urgentMaxTurn: 20, surfaceLift: 0.04,
    textContrast: Palette.TEXT_RATIO, urgentRed: "#c0392b"
  })
  readonly property var fallback: ({
    background: "#0b0e14", foreground: "#bfbdb6", accent: "#39bae6", accent2: "#ffb454", urgent: "#f07178",
    muted: "#565b66"
  })

  function wal(bg, fg, c1, c4) {
    return { special: { background: bg, foreground: fg },
      colors: { color1: c1, color2: "#2C8A89", color3: "#894547", color4: c4, color5: "#AE6B6E", color6: "#DBD3B2",
        color8: "#9D9678" } }
  }

  function readable(p, role) {
    for (const bg of [p.background, p.surface])
      verify(Palette.contrast(Palette.hexToRgb(p[role]), Palette.hexToRgb(bg)) >= Palette.TEXT_RATIO,
        role + " " + p[role] + " on " + bg)
  }

  function test_derived_palette_data() {
    return [
      { tag: "teal color1, dark", raw: wal("#0A1115", "#F5ECCA", "#417A8D", "#2F86A3") },
      { tag: "teal color1, light", raw: wal("#EEEAD9", "#0A1115", "#417A8D", "#2F86A3") },
      { tag: "gruvbox-light", raw: wal("#fbf1c7", "#3c3836", "#cc241d", "#3d7678") }
    ]
  }

  function test_derived_palette(data) {
    const p = Palette.conditionPalette(data.raw, fallback, knobs)
    const hue = Palette.hueDeg(Palette.hexToRgb(p.urgent))
    verify(hue >= Palette.URGENT_HUE_MIN_DEG || hue <= Palette.URGENT_HUE_MAX_DEG, "urgent " + p.urgent + " is red")
    readable(p, "accentText")
    readable(p, "textDim")
    verify(Palette.contrast(Palette.hexToRgb(p.textDim), Palette.hexToRgb(p.background))
      < Palette.contrast(Palette.hexToRgb(p.foreground), Palette.hexToRgb(p.background)), "textDim below foreground")
  }

  function test_vivify_keeps_text_contrast() {
    const bg = Palette.hexToRgb("#fbf1c7")
    const color4 = Palette.hexToRgb("#3d7678")
    verify(Palette.passes(color4, bg, Palette.TEXT_RATIO))
    verify(Palette.passes(Palette.vivifyOn(bg, color4, 0.7, 0.62, Palette.TEXT_RATIO), bg, Palette.TEXT_RATIO))
  }
}
'

def main [] {
    let dir = mktemp --directory
    # remove the temp dir whether the run succeeds or a step throws
    let outcome = try {
        mkdir ($dir | path join utiltest)
        open --raw $UTIL | str replace --regex '(?m)^import Quickshell\n' '' | save ($dir | path join utiltest Util.qml)
        "module utiltest\nsingleton Util 1.0 Util.qml\n" | save ($dir | path join utiltest qmldir)
        cp $PALETTE ($dir | path join utiltest Palette.js)
        $TEST | save ($dir | path join tst_util.qml)
        with-env {QT_QPA_PLATFORM: offscreen} { ^$RUNNER -import $dir -input ($dir | path join tst_util.qml) } | complete
    } catch {|e| {failed: $e.msg} }
    rm --recursive --force $dir
    if ($outcome | get --optional failed) != null { error make {msg: $outcome.failed} }
    if $outcome.exit_code != 0 { error make {msg: $"qmltestrunner failed\n($outcome.stdout)($outcome.stderr)"} }
}
