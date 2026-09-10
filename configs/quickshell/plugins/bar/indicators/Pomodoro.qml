// New indicator, not from omarchy-shell (it has no pomodoro). Same shape as
// Reminder.qml: poll a script's `status --json`, show a glyph while active.
// scripts/pomodoro.sh owns all the state and the systemd timers, so this is
// purely a readout — the bar can be restarted mid-focus and the countdown
// picks up exactly where it was.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Glyphs verified by name in the 0xProto Nerd Font cmap: md-timer_sand
// U+F051F, md-coffee U+F0176.
BarIndicator {
    id: root

    readonly property string pomodoroScript: Quickshell.env("HOME") + "/.local/bin/pomodoro"
    property bool running: false
    property bool paused: false
    property string phase: "idle"
    property string remaining: ""
    property string tooltip: "Pomodoro: off"

    function refresh() {
        if (!jsonProc.running)
            jsonProc.running = true;

    }

    function update(raw) {
        try {
            var d = JSON.parse(raw || "{}");
            root.running = !!d.running;
            root.paused = !!d.paused;
            root.phase = String(d.phase || "idle");
            root.remaining = String(d.remaining || "");
            root.tooltip = String(d.tooltip || "Pomodoro: off");
        } catch (e) {
            root.running = false;
            root.tooltip = "Pomodoro: off";
        }
    }

    active: running
    // A break gets the coffee cup, so the phase is readable at a glance
    // without opening the clock panel.
    activeText: phase === "work" ? "\u{f051f}" : "\u{f0176}"
    inactiveText: "\u{f051f}"
    activeTooltipText: tooltip
    inactiveTooltipText: tooltip
    // Click cycles start -> pause -> resume, the one action worth having
    // without opening a panel. Stop/skip live in the clock panel.
    onPressed: function() {
        Quickshell.execDetached([root.pomodoroScript, "toggle"]);
        Qt.callLater(root.refresh);
    }

    Process {
        id: jsonProc

        command: [root.pomodoroScript, "status", "--json"]
        onExited: function(exitCode) {
            if (exitCode !== 0)
                root.running = false;

        }

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.update(text)
        }

    }

    // 10s, matching Reminder.qml rather than the 20s catch-up polls: like
    // reminders, this indicator has no push path — the phase can roll over
    // from a systemd timer with nothing to tell the bar about it. The clock
    // panel polls faster while it is actually open (see Clock.qml).
    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

}
