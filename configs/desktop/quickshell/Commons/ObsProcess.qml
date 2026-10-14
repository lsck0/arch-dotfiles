import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
pragma Singleton

// the obs widget owns the websocket helper and mirrors its state here for the audio mixer
Singleton {
    id: root

    property bool running: false
    property bool connected: false
    // panel label (Mic/Media/Voice/Game) -> 0..1 multiplier
    property var inputVolumes: ({
    })
    property var inputMutes: ({
    })

    // the obs widget forwards these to the helper
    signal commandRequested(var command)

    function send(command) {
        root.commandRequested(command);
    }

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

    // a tray quit closes no window, so poll while obs runs
    Timer {
        interval: 60000
        running: root.running
        repeat: true
        onTriggered: root.probe()
    }

}
