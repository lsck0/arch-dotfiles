#!/usr/bin/env -S nu --no-config-file
# Util.qml's text helpers and Palette.js's derived palette under qmltestrunner, Util alone in a module so the service
# singletons stay unloaded

use ../scripts/lib/qml-test.nu [qml-test-run]

const UTIL = path self Util.qml
const PALETTE = path self Palette.js
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

  function test_map_copies() {
    var base = { a: 1, b: 2 }
    compare(Util.mapSet(base, "c", 3).c, 3)
    verify(!("b" in Util.mapWithout(base, "b")))
    compare(base.b, 2)
  }

  function test_parse_object() {
    compare(Util.parseObject("{\"a\": 1}").a, 1)
    compare(Object.keys(Util.parseObject("")).length, 0)
    compare(Object.keys(Util.parseObject("[1]")).length, 0)
    compare(Object.keys(Util.parseObject("{broken")).length, 0)
  }

  function test_alpha() {
    compare(Util.alpha("#ff0000", 0.5).a, 0.5)
    compare(Util.alpha("#ff0000", 0.5).r, 1)
    compare(Util.alpha("#ff0000", 2).a, 1)
    compare(Util.alpha("#ff0000", -1).a, 0)
    compare(Util.alpha("#ff0000", undefined).a, 0)
    compare(Util.alpha(null, 1).r, 0)
  }

  function test_bytes() {
    compare(Util.bytes(0), "0B")
    compare(Util.bytes(340 * 1024), "340K")
    compare(Util.bytes(512 * Util.bytesPerMib), "512M")
    compare(Util.bytes(1.5 * Util.bytesPerMib), "1.5M")
    compare(Util.bytes(29.5 * Util.bytesPerGib), "29.5G")
    compare(Util.bytes(undefined), "0B")
    compare(Util.bytesOf(29.5 * Util.bytesPerGib, 60 * Util.bytesPerGib), "29.5/60G")
    compare(Util.bytesOf(512 * Util.bytesPerMib, 8 * Util.bytesPerGib), "0.5/8G")
    compare(Util.bytesOf(60 * Util.bytesPerGib, 60 * Util.bytesPerGib), "60.0/60G")
  }

  function test_count() {
    compare(Util.count(0, "reminder"), "0 reminders")
    compare(Util.count(1, "reminder"), "1 reminder")
    compare(Util.count(2, "reminder"), "2 reminders")
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
    accent2Contrast: 3, urgentMinApart: 40, urgentMaxTurn: 20, surfaceLift: 0.04,
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
    qml-test-run $TEST {|dir|
        let module = $dir | path join utiltest
        mkdir $module
        open --raw $UTIL | str replace --all --regex '(?m)^import Quickshell.*\n' '' | save ($module | path join Util.qml)
        "module utiltest\nsingleton Util 1.0 Util.qml\n" | save ($module | path join qmldir)
        cp $PALETTE ($module | path join Palette.js)
    }
}
