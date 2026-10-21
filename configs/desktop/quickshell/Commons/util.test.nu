#!/usr/bin/env -S nu --no-config-file
# Util.qml's text helpers under qmltestrunner, Util alone in a module so the service singletons stay unloaded

const UTIL = path self | path dirname | path join Util.qml
const RUNNER = "/usr/lib/qt6/bin/qmltestrunner"
const TEST = '
import QtQuick
import QtTest
import utiltest

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
}
'

def main [] {
    let dir = mktemp --directory
    mkdir ($dir | path join utiltest)
    open --raw $UTIL | str replace --regex '(?m)^import Quickshell\n' '' | save ($dir | path join utiltest Util.qml)
    "module utiltest\nsingleton Util 1.0 Util.qml\n" | save ($dir | path join utiltest qmldir)
    $TEST | save ($dir | path join tst_util.qml)
    let run = with-env {QT_QPA_PLATFORM: offscreen} { ^$RUNNER -import $dir -input ($dir | path join tst_util.qml) } | complete
    rm --recursive --force $dir
    if $run.exit_code != 0 { error make {msg: $"qmltestrunner failed\n($run.stdout)($run.stderr)"} }
}
