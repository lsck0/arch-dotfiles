#!/usr/bin/env -S nu --no-config-file
# NotificationLogic.js under qmltestrunner: the toast's action filter, the sender name of a snapshot, the history list

const LOGIC = path self | path dirname | path join NotificationLogic.js
const RUNNER = "/usr/lib/qt6/bin/qmltestrunner"
const TEST = '
import QtQuick
import QtTest
import "NotificationLogic.js" as NotificationLogic

TestCase {
  name: "notifications"

  function test_hidden_action() {
    verify(NotificationLogic.isHiddenAction("mail-mark-read", "Mark as read"))
    verify(NotificationLogic.isHiddenAction("anything", "Mark as Read"))
    verify(NotificationLogic.isHiddenAction("mark", ""))
    verify(!NotificationLogic.isHiddenAction("reply", "Reply"))
    verify(!NotificationLogic.isHiddenAction("default", "Open"))
  }

  function test_snapshot_app() {
    compare(NotificationLogic.snapshotOf({ id: 1, appName: "Telegram Desktop" }, 5, "Telegram").app, "Telegram Desktop")
    compare(NotificationLogic.snapshotOf({ id: 1, appName: "", desktopEntry: "org.telegram.desktop" }, 5, "Telegram").app, "Telegram")
    compare(NotificationLogic.snapshotOf({ id: 1, appName: "", desktopEntry: "org.telegram.desktop" }, 5, "").app, "org.telegram.desktop")
    compare(NotificationLogic.snapshotOf({ id: 1, appName: "notify-send", desktopEntry: "timeshift" }, 5, "Timeshift").app, "Timeshift")
    compare(NotificationLogic.snapshotOf({ id: 1, appName: "notify-send" }, 5, "").app, "notify-send")
    compare(NotificationLogic.snapshotOf({ id: 1, appIcon: "gtk-dialog-info" }, 5, "", "").appIcon, "dialog-info")
    compare(NotificationLogic.snapshotOf({ id: 1, appIcon: "" }, 5, "", "timeshift").appIcon, "timeshift")
    compare(NotificationLogic.replacementSnapshot({ id: 9, appName: "" }, 3, 5, "ZapZap").app, "ZapZap")
  }

  function test_history_list() {
    var entry = function(id, t) { return JSON.stringify({ originalId: id, timestamp: t }) }
    var raw = [entry(1, 10), entry(2, 30), entry(1, 10), "not json", "[1]", "", entry(3, 20)].join("\n")
    var rows = NotificationLogic.historyList(raw)
    compare(rows.length, 3)
    compare(rows.map(function(r) { return r.timestamp }).join(","), "30,20,10")
    compare(NotificationLogic.historyList("").length, 0)
  }

  function test_parse_exec_argv() {
    compare(NotificationLogic.parseExecArgv(JSON.stringify(["xdg-open", "https://example.com"]))[1], "https://example.com")
    verify(NotificationLogic.parseExecArgv(JSON.stringify(["xdg-open", "http://example.com"])) === null)
    verify(NotificationLogic.parseExecArgv(JSON.stringify(["xdg-open", "https://x", "extra"])) === null)
    verify(NotificationLogic.parseExecArgv(JSON.stringify(["firefox", "https://x"])) === null)
    verify(NotificationLogic.parseExecArgv(JSON.stringify(["xdg-open", "https://e\u0001vil"])) === null)
    verify(NotificationLogic.parseExecArgv("not json") === null)
  }

  function test_strip_image_tags() {
    compare(NotificationLogic.stripImageTags("<img src=x>hello"), "hello")
    compare(NotificationLogic.stripImageTags("<i<img>mg src=x>hello"), "hello")
    compare(NotificationLogic.stripImageTags("plain text"), "plain text")
  }
}
'

def main [] {
    let dir = mktemp --directory
    # remove the temp dir whether the run succeeds or a step throws
    let outcome = try {
        cp $LOGIC $dir
        $TEST | save ($dir | path join tst_notifications.qml)
        with-env {QT_QPA_PLATFORM: offscreen} { ^$RUNNER -input ($dir | path join tst_notifications.qml) } | complete
    } catch {|e| {failed: $e.msg} }
    rm --recursive --force $dir
    if ($outcome | get --optional failed) != null { error make {msg: $outcome.failed} }
    if $outcome.exit_code != 0 { error make {msg: $"qmltestrunner failed\n($outcome.stdout)($outcome.stderr)"} }
}
