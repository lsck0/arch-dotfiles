#!/usr/bin/env -S nu --no-config-file
# NotificationLogic.js under qmltestrunner: the toast's action filter and the sender name of a snapshot

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
}
'

def main [] {
    let dir = mktemp --directory
    cp $LOGIC $dir
    $TEST | save ($dir | path join tst_notifications.qml)
    let run = with-env {QT_QPA_PLATFORM: offscreen} { ^$RUNNER -input ($dir | path join tst_notifications.qml) } | complete
    rm --recursive --force $dir
    if $run.exit_code != 0 { error make {msg: $"qmltestrunner failed\n($run.stdout)($run.stderr)"} }
}
