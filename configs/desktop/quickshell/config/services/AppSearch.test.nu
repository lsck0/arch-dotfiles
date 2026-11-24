#!/usr/bin/env -S nu --no-config-file
# AppSearch.js's launcher order under qmltestrunner: how the query matched ranks first, frecency next, so a launched
# app is not pushed below a rarely used one only for a shorter name.

use ../scripts/lib/qml-test.nu [qml-test-run]

const SEARCH = path self AppSearch.js
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
    qml-test-run $TEST {|dir| cp $SEARCH $dir }
}
