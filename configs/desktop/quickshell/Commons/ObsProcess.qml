import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
pragma Singleton

// the obs widget owns the websocket helper and mirrors its state here for the audio mixer
Singleton {
    id: root

    property bool running: false
    property bool probed: false
    property bool connected: false
    // hearing obs's stream mix instead of the system audio (scripts/toggles/toggle-obs-listen.nu)
    property bool listening: false
    readonly property string listenScript: Paths.toggle("toggle-obs-listen.nu")
    property var inputVolumes: ({
    })
    property var inputMutes: ({
    })

    signal commandRequested(var command)

    function send(command) {
        root.commandRequested(command);
    }

    function listenSet(on) {
        if (on !== root.listening)
            Quickshell.execDetached([root.listenScript, on ? "on" : "off"]);

    }

    function listenRefresh() {
        if (!listenProc.running)
            listenProc.running = true;

    }

    function probe() {
        if (!proc.running)
            proc.running = true;

    }

    Component.onCompleted: {
        root.probe();
        root.listenRefresh();
    }

    Process {
        id: listenProc

        command: [root.listenScript, "get"]
        onExited: root.listening = (listenOutput.text || "").trim() === "on"

        stdout: StdioCollector {
            id: listenOutput

            waitForEnd: true
        }

    }

    Connections {
        function onChanged(script) {
            if (script === "toggle-obs-listen.nu")
                root.listenRefresh();

        }

        target: ToggleEvents
    }

    IpcHandler {
        function toggleListen(): void {
            root.listenSet(!root.listening);
        }

        function listen(on: bool): void {
            root.listenSet(on);
        }

        function listening(): string {
            return root.listening ? "on" : "off";
        }

        target: "obs"
    }

    Process {
        id: proc

        // -x, pgrep -f would match its own command line
        command: ["pgrep", "-x", "obs"]
        onExited: function(exitCode) {
            root.running = exitCode === 0;
            root.probed = true;
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
