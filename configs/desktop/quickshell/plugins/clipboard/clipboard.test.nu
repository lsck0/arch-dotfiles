#!/usr/bin/env -S nu --no-config-file
# ClipboardHistory.js under qmltestrunner: an entry's stamp survives a save and a load, a re-copy refreshes it, and the
# age limit drops what is older

const LOGIC = path self ClipboardHistory.js
const RUNNER = "/usr/lib/qt6/bin/qmltestrunner"
const TEST = '
import QtQuick
import QtTest
import "ClipboardHistory.js" as ClipboardHistory

TestCase {
  name: "clipboard"

  function test_stamp_round_trip() {
    var history = ClipboardHistory.addEntry([], { type: "text", text: "a" }, 10, 1000)
    compare(history[0].addedMs, 1000)
    var loaded = ClipboardHistory.parseHistory(JSON.stringify(history))
    compare(loaded[0].addedMs, 1000)
    verify(!ClipboardHistory.stampUnstamped(loaded, 5000))
    compare(loaded[0].addedMs, 1000)
  }

  function test_unstamped_counts_from_load() {
    var loaded = ClipboardHistory.parseHistory(JSON.stringify([{ type: "text", text: "old" }, "bare"]))
    verify(ClipboardHistory.stampUnstamped(loaded, 5000))
    compare(loaded.map(function (e) { return e.addedMs }).join(","), "5000,5000")
  }

  function test_recopy_refreshes() {
    var history = ClipboardHistory.addEntry([], { type: "text", text: "a" }, 10, 1000)
    history = ClipboardHistory.addEntry(history, { type: "text", text: "b" }, 10, 2000)
    history = ClipboardHistory.addEntry(history, { type: "text", text: "a" }, 10, 3000)
    compare(history.map(function (e) { return e.text + e.addedMs }).join(","), "a3000,b2000")
  }

  function test_expire() {
    var history = [
      { type: "text", text: "new", addedMs: 900 },
      { type: "image", path: "/run/x.png", mime: "image/png", addedMs: 500 },
      { type: "text", text: "old", addedMs: 100 }
    ]
    compare(ClipboardHistory.expireEntries(history, 1000, 600).length, 2)
    compare(ClipboardHistory.expireEntries(history, 1100, 600).map(function (e) { return e.addedMs }).join(","), "900")
    compare(ClipboardHistory.expiryDueMs(history, 400, 600), 300)
    compare(ClipboardHistory.expiryDueMs(history, 2000, 600), 0)
    compare(ClipboardHistory.expiryDueMs([], 2000, 600), -1)
  }
}
'

def main [] {
    let dir = mktemp --directory
    # remove the temp dir whether the run succeeds or a step throws
    let outcome = try {
        cp $LOGIC $dir
        $TEST | save ($dir | path join tst_clipboard.qml)
        with-env {QT_QPA_PLATFORM: offscreen} { ^$RUNNER -input ($dir | path join tst_clipboard.qml) } | complete
    } catch {|e| {failed: $e.msg} }
    rm --recursive --force $dir
    if ($outcome | get --optional failed) != null { error make {msg: $outcome.failed} }
    if $outcome.exit_code != 0 { error make {msg: $"qmltestrunner failed\n($outcome.stdout)($outcome.stderr)"} }
}
