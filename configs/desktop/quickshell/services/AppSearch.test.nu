#!/usr/bin/env -S nu --no-config-file
# AppSearch.js's launcher order under qmltestrunner: how the query matched ranks first, frecency next, so a launched
# app is not pushed below a rarely used one only for a shorter name.

const SEARCH = path self AppSearch.js
const RUNNER = "/usr/lib/qt6/bin/qmltestrunner"
const TEST = '
import QtQuick
import QtTest
import "AppSearch.js" as AppSearch

TestCase {
  name: "appsearch"

  readonly property var entries: [
    { id: "io.github.ProtonVPN", name: "Proton VPN" },
    { id: "proton-mail", name: "Proton Mail" },
    { id: "org.gnome.Nautilus", name: "Files" },
    { id: "firefox", name: "Firefox" },
    { id: "tracy", name: "Tracy", comment: "profiler for code" },
    { id: "code-oss", name: "Code - OSS" }
  ]
  readonly property var launches: ({ "proton-mail": 28, "io.github.ProtonVPN": 2, "firefox": 9, "tracy": 50 })

  function order(query) {
    return AppSearch.sortedEntries(entries, query, null, function(e) { return launches[e.id] || 0 })
      .map(function(e) { return e.name })
  }

  function test_order_data() {
    return [
      { tag: "frecency within a name prefix", query: "pro", want: ["Proton Mail", "Proton VPN", "Tracy"] },
      { tag: "frecency within a name prefix, fi", query: "fi", want: ["Firefox", "Files", "Tracy"] },
      { tag: "a name prefix above a used comment match", query: "code", want: ["Code - OSS", "Tracy"] },
      { tag: "no query: frecency, then name", query: "", want: ["Tracy", "Proton Mail", "Firefox", "Proton VPN", "Code - OSS", "Files"] }
    ]
  }

  function test_order(data) {
    compare(JSON.stringify(order(data.query)), JSON.stringify(data.want))
  }

  function test_no_match() {
    compare(order("zzz").length, 0)
  }
}
'

def main [] {
    let dir = mktemp --directory
    # remove the temp dir whether the run succeeds or a step throws
    let outcome = try {
        cp $SEARCH ($dir | path join AppSearch.js)
        $TEST | save ($dir | path join tst_appsearch.qml)
        with-env {QT_QPA_PLATFORM: offscreen} { ^$RUNNER -input ($dir | path join tst_appsearch.qml) } | complete
    } catch {|e| {failed: $e.msg} }
    rm --recursive --force $dir
    if ($outcome | get --optional failed) != null { error make {msg: $outcome.failed} }
    if $outcome.exit_code != 0 { error make {msg: $"qmltestrunner failed\n($outcome.stdout)($outcome.stderr)"} }
}
