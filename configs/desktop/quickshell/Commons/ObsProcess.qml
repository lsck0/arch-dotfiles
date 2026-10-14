import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
pragma Singleton

// whether obs runs, shared by the bar's obs widget and the notification service's auto dnd.
// the obs widget also owns the obs-websocket helper and publishes the slice the audio mixer
// needs here: connection state, per-input volume and mute, and a channel back for its commands.
Singleton {
    id: root

    property bool running: false
    // set by the obs widget from the helper stream
    property bool connected: false
    // panel label (Mic/Media/Voice/Game) -> obs input volume multiplier, 0..1
    property var inputVolumes: ({
    })
    // panel label -> obs input muted
    property var inputMutes: ({
    })

    // the audio mixer sends obs commands through here; the obs widget writes them to the helper
    signal commandRequested(var command)

    function send(command) {
        root.commandRequested(command);
    }

    // toplevel changes catch launch and window close; the slow poll catches a quit from the tray
    function probe() {
        if (!proc.running)
            proc.running = true;

    }

    // obs may already run when the shell starts
    Component.onCompleted: root.probe()

    Process {
        id: proc

        // -x, pgrep -f would match its own command line
        command: ["pgrep", "-x", "obs"]
        onExited: function(exitCode) {
            root.running = exitCode === 0;
        }
    }

    Connections {
        function onValuesChanged() {
            root.probe();
        }

        target: ToplevelManager.toplevels
    }

    // only while obs runs, to catch a tray quit that closes no window; a launch is caught by the toplevel event
    Timer {
        interval: 60000
        running: root.running
        repeat: true
        onTriggered: root.probe()
    }

}
