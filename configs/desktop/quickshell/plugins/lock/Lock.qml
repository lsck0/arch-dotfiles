pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// session lock is fail-secure; no unlock ipc on purpose (auth bypass)
Item {
    id: root

    property bool locked: false
    property bool authError: false
    property string primaryScreenName: ""
    // in-flight pam response; the field enter was pressed in is the source of truth
    property string _pw: ""
    property var activeField: null
    // notifications that arrived since this
    property real lockedAtMs: 0
    // security key mode: its own pam service and its own field content, so the password and the pin never cross
    property bool keyMode: false
    property string _pin: ""
    property string keyDevice: ""
    // -1 until the key answered
    property int pinRetries: -1
    // ctap2's floor until the key reports its own; a shorter pin could only cost an attempt
    property int pinLengthMin: 4
    property string keyCue: ""
    property string keyNote: ""
    // a plug event lands as a burst, one line per hid interface
    readonly property int keyProbeSettleMs: 250
    // the field's placeholder stays hidden while it has focus, so this line labels the pin field
    readonly property string keyStatus: {
        if (pamU2f.active)
            return root.keyCue !== "" ? root.keyCue : "waiting for security key";

        var retries = root.pinRetries >= 0 ? root.pinRetries + " PIN attempts left" : "";
        if (root.keyNote !== "")
            return retries !== "" ? root.keyNote + ", " + retries : root.keyNote;

        if (root.keyMode)
            return retries !== "" ? "security key PIN, " + retries : "security key PIN";

        return "";
    }
    property string statsText: ""
    readonly property int ambientMs: 30000
    // notification dock: app and time only, summaries and bodies never reach the lock screen
    readonly property string notesDir: Paths.state + "/notifications"
    readonly property int notesShown: 3
    property var notes: []
    // the playing player, else the first one with a title
    readonly property var player: {
        // quickshell ships ObjectModel to the Mpris qmltypes as an opaque stub, so its values are invisible to qmllint
        var list = Mpris.players.values; // qmllint disable missing-property
        var fallback = null;
        for (let i = 0; i < list.length; i++) {
            if (list[i].playbackState === MprisPlaybackState.Playing)
                return list[i];

            if (!fallback && list[i].trackTitle)
                fallback = list[i];

        }
        return fallback;
    }
    readonly property string mediaText: player && player.trackTitle ? (player.playbackState === MprisPlaybackState.Playing ? "> " : "|| ") + (player.trackArtist ? player.trackArtist + " :: " : "") + player.trackTitle : ""
    property string clockText: "00//00//00"
    property string dateText: ""

    signal clearFields()
    signal glitchOut()

    function lock() {
        // a lock during the unlock glitch cancels the unlock
        if (unlockDelay.running) {
            unlockDelay.stop();
            return ;
        }
        if (root.locked) {
            // held or still pending: an unlock before the compositor confirms is a protocol error that kills quickshell
            if (sessionLock.locked)
                return ;

            // the compositor refused or dropped the lock: re-arm it rather than stay unlocked behind locked == true
            root.locked = false;
        }
        root.lockedAtMs = Date.now();
        root.notes = [];
        root.authError = false;
        root._pw = "";
        var scr = Quickshell.screens;
        root.primaryScreenName = (scr && scr.length) ? String(scr[0].name) : "";
        root.locked = true;
    }

    // only a successful pam result may call this; the glitch plays out first, then the lock drops
    function unlock() {
        root.authError = false;
        root._pw = "";
        root.clearFields();
        pamPw.active = false;
        root.glitchOut();
        unlockDelay.restart();
    }

    function submit() {
        if (!root.locked || !root.activeField || root.activeField.text.length === 0)
            return ;

        root._pw = root.activeField.text;
        root.authError = false;
        pamPw.start();
    }

    function fail() {
        root.authError = true;
        root._pw = "";
        root.clearFields();
    }

    function keyModeEnter() {
        if (!root.locked || root.keyMode || root.keyDevice === "" || pamPw.active)
            return ;

        root._pw = "";
        root.clearFields();
        root.authError = false;
        root.keyNote = "";
        root.pinRetries = -1;
        root.keyMode = true;
        retriesProc.running = true;
    }

    function keyModeLeave() {
        root.keyMode = false;
        root._pin = "";
        root.keyCue = "";
        root.clearFields();
        if (pamU2f.active)
            pamU2f.abort();

    }

    function submitPin() {
        // the info query holds the device; pam_u2f would fail to open it
        if (!root.locked || !root.keyMode || pamU2f.active || retriesProc.running)
            return ;

        if (!root.activeField || root.activeField.text.length === 0)
            return ;

        if (root.activeField.text.length < root.pinLengthMin) {
            root.keyNote = "PIN too short";
            root.clearFields();
            return ;
        }
        root._pin = root.activeField.text;
        root.clearFields();
        root.keyNote = "";
        root.keyCue = "";
        pamU2f.start();
    }

    function keyFail(note) {
        root.keyModeLeave();
        root.authError = true;
        root.keyNote = note;
        if (root.keyDevice !== "")
            retriesProc.running = true;

    }

    // a marker in tmpfs while locked: a quickshell that crashed or restarted under the lock locks again at start,
    // hyprland's allow_session_lock_restore hands the lock to the new instance
    readonly property string lockMarker: Paths.runtime + "/locked"

    onLockedChanged: {
        root.keyMode = false;
        root._pin = "";
        root.keyCue = "";
        root.keyNote = "";
        if (root.locked)
            keyProbe.running = true;

        Quickshell.execDetached(root.locked ? ["install", "-D", "-m", "600", "/dev/null", root.lockMarker] : ["rm", "-f", root.lockMarker]);
    }
    Component.onCompleted: markerProbe.running = true

    Process {
        id: markerProbe

        command: ["test", "-e", root.lockMarker]
        onExited: function(exitCode) {
            if (exitCode === 0)
                root.lock();

        }
    }

    onKeyDeviceChanged: {
        if (root.keyDevice === "" && root.keyMode && !pamU2f.active) {
            root.keyModeLeave();
        }
    }

    Timer {
        id: unlockDelay

        // Glitch.durationMs; instant when motion is off
        interval: Style.motion.enabled ? 180 : 0
        onTriggered: root.locked = false
    }

    IpcHandler {
        function lock() : string {
            root.lock();
            return "ok";
        }

        // the compositor-granted state, not the request: the launcher falls back to hyprlock on it; a pending unlock
        // counts as unlocked so the launcher still sends its lock, which cancels it
        function isLocked() : string {
            return sessionLock.secure && !unlockDelay.running ? "true" : "false";
        }

        target: "lock"
    }

    PamContext {
        id: pamPw

        config: "quickshell-lock"
        onResponseRequiredChanged: {
            if (responseRequired) {
                respond(root._pw);
            }
        }
        onCompleted: function(result) {
            if (result === PamResult.Success)
                root.unlock();
            else
                root.fail();
            active = false;
        }
        onError: function(err) {
            root.fail();
            active = false;
        }
    }

    PamContext {
        id: pamU2f

        config: "quickshell-lock-u2f"
        onPamMessage: {
            if (!responseRequired) {
                if (messageIsError)
                    root.keyNote = message;
                else
                    root.keyCue = message;
                return ;
            }
            // one pin per start: a second prompt (another key, a retry) would spend another attempt on the same pin
            if (root._pin === "") {
                root.keyFail("security key asked twice");
                return ;
            }
            respond(root._pin);
            root._pin = "";
        }
        onCompleted: function(result) {
            if (result === PamResult.Success)
                root.unlock();
            else if (root.keyMode)
                root.keyFail("security key failed");
            active = false;
        }
        onError: function(err) {
            if (root.keyMode)
                root.keyFail("security key failed");

            active = false;
        }
    }

    // any fido key, found by its hid usage page; the first one listed is the one asked
    Process {
        id: keyProbe

        command: ["fido2-token", "-L"]

        stdout: StdioCollector {
            onStreamFinished: {
                var device = String(text).match(/^(\/dev\/hidraw[0-9]+):/m);
                root.keyDevice = device ? device[1] : "";
            }
        }

    }

    Timer {
        id: keyProbeSettle

        interval: root.keyProbeSettleMs
        onTriggered: {
            if (!keyProbe.running) {
                keyProbe.running = true;
            }
        }
    }

    Process {
        running: root.locked
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=hidraw"]

        stdout: SplitParser {
            onRead: function(line) {
                if (line.indexOf("(hidraw)") >= 0)
                    keyProbeSettle.restart();

            }
        }

    }

    // getInfo and getPinRetries: no pin, no touch, no attempt spent
    Process {
        id: retriesProc

        command: ["fido2-token", "-I", root.keyDevice]

        stdout: StdioCollector {
            onStreamFinished: {
                var retries = String(text).match(/^pin retries: ([0-9]+)$/m);
                var lengthMin = String(text).match(/^minpinlen: ([0-9]+)$/m);
                root.pinRetries = retries ? Number(retries[1]) : -1;
                if (lengthMin)
                    root.pinLengthMin = Number(lengthMin[1]);

            }
        }

    }

    Process {
        id: statsProc

        command: ["timeout", "4s", Paths.home + "/.config/hypr/lockscreen-stats.nu"]

        stdout: StdioCollector {
            onStreamFinished: root.statsText = String(text).trim()
        }

    }
    // stats and the notification dock are ambient, not live

    Timer {
        interval: root.ambientMs
        running: root.locked
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!statsProc.running)
                statsProc.running = true;

            if (!notesProc.running)
                notesProc.running = true;

        }
    }

    Process {
        id: notesProc

        command: ["bash", "-c", "cat \"$1\"/*.json \"$1\"/history/*.json 2>/dev/null" + " | jq -s -c --argjson since \"$2\" '[.[] | select((.timestamp // 0) >= $since)" + " | {app: (.app // \"\"), timestamp}] | unique_by([.timestamp, .app]) | sort_by(-.timestamp)'", "--", root.notesDir, String(Math.floor(root.lockedAtMs))]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text || "[]");
                    root.notes = Array.isArray(parsed) ? parsed : [];
                } catch (e) {
                    root.notes = [];
                }
            }
        }

    }

    Timer {
        interval: 1000
        running: root.locked
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var now = new Date();
            root.clockText = Qt.formatDateTime(now, "HH//mm//ss");
            root.dateText = Qt.formatDateTime(now, ">> dd/MM/yy");
        }
    }

    WlSessionLock {
        id: sessionLock

        locked: root.locked

        // projection and the auth hud on every screen: hyprland gives the keyboard to the surface under the cursor
        WlSessionLockSurface {
            id: surface

            // QuickshellScreenInfo is an opaque stub in quickshell's window qmltypes, so its name is invisible to qmllint
            readonly property bool isPrimary: root.primaryScreenName === "" || (screen && String(screen.name) === root.primaryScreenName) // qmllint disable missing-property

            color: Colors.background
            onVisibleChanged: {
                if (visible) {
                    Qt.callLater(function() {
                    pwField.forceActiveFocus();
                    glitch.play();
                });
                }
            }
            Component.onCompleted: Qt.callLater(function() {
                pwField.forceActiveFocus();
                glitch.play();
            })

            // what the glitch captures
            Item {
                id: lockContent

                anchors.fill: parent

                // faint blurred wallpaper; unset while unlocked so each lock decodes the current one
                Image {
                    id: wallpaper

                    anchors.fill: parent
                    source: root.locked ? Util.fileUrl(Quickshell.env("HOME") + "/.cache/wal/wallpaper") : ""
                    cache: false
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: {
                        // QuickshellScreenInfo is an opaque stub in quickshell's window qmltypes
                        const dpr = surface.screen && surface.screen.devicePixelRatio ? surface.screen.devicePixelRatio : 1; // qmllint disable missing-property
                        return Qt.size(surface.width * dpr, surface.height * dpr);
                    }
                    opacity: 0.35
                    layer.enabled: true

                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 1
                        blurMax: 64
                    }

                }

                // theme wash: the dim wallpaper alone reads as a washed photo, this ties the lock to the pywal palette
                Rectangle {
                    anchors.fill: parent

                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.7)
                        }

                        GradientStop {
                            position: 1
                            color: Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.22)
                        }

                    }

                }

                AsciiProjection {
                    id: projection

                    anchors.fill: parent
                    image: wallpaper
                    active: root.locked && surface.visible
                    animate: Style.fx.matrixRain > 0 && Style.motion.enabled
                }

                Column {
                    anchors.centerIn: parent
                    spacing: Style.spacing.sm

                    // the lock's hero is twice the shell's
                    Hero {
                        anchors.horizontalCenter: parent.horizontalCenter
                        value: root.clockText
                        size: Style.font.hero * 2
                        live: true
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        textFormat: Text.PlainText
                        text: root.dateText
                        color: Colors.foreground
                        opacity: Style.emphasis.dim
                        font.family: Style.font.family
                        font.pixelSize: Style.font.title
                        font.letterSpacing: Style.headerTracking
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.mediaText !== ""
                        width: Math.min(implicitWidth, Style.space(480))
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: root.mediaText
                        color: Colors.accent
                        opacity: Style.emphasis.dim
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Style.space(320)
                        height: Style.space(46)
                        color: Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, 0.55)
                        border.width: root.authError ? 2 : 1
                        border.color: root.authError ? Colors.urgent : (pwField.activeFocus ? Colors.accent : Style.normalBorderColor)
                        radius: Style.shape.data
                        // hidden until typing starts; keeps focus, so the first key still lands in the field
                        opacity: (pwField.text.length > 0 || root.authError || pamPw.active || root.keyMode) ? 1 : 0

                        // the field takes input but draws nothing; the row below shows one * per char and a block cursor
                        TextField {
                            id: pwField

                            anchors.fill: parent
                            anchors.margins: Style.spacing.xs
                            echoMode: TextInput.Password
                            enabled: root.locked
                            color: "transparent"
                            selectionColor: "transparent"
                            selectedTextColor: "transparent"
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                            font.letterSpacing: Style.labelTracking
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            placeholderText: root.authError ? "  ACCESS DENIED" : "> AUTH REQUIRED"
                            placeholderTextColor: root.authError ? Colors.urgent : Qt.darker(Colors.foreground, 1.6)
                            background: null
                            onTextEdited: {
                                root.authError = false;
                                if (!root.keyMode)
                                    root.keyNote = "";

                            }
                            onAccepted: {
                                root.activeField = pwField;
                                if (root.keyMode)
                                    root.submitPin();
                                else
                                    root.submit();
                            }
                            Keys.onEscapePressed: {
                                if (root.keyMode)
                                    root.keyModeLeave();
                                else
                                    text = "";
                            }
                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) {
                                    root.keyModeEnter();
                                    event.accepted = true;
                                }
                            }

                            Connections {
                                function onClearFields() {
                                    pwField.text = "";
                                }

                                target: root
                            }

                            cursorDelegate: Item {
                            }

                        }

                        Row {
                            anchors.centerIn: parent
                            visible: pwField.text.length > 0
                            spacing: 0

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                // capped so a long passphrase never outgrows the box
                                width: Math.min(implicitWidth, Style.space(280))
                                elide: Text.ElideLeft
                                textFormat: Text.PlainText
                                text: "*".repeat(pwField.text.length)
                                color: Colors.foreground
                                font.family: Style.font.family
                                font.pixelSize: Style.font.body
                                font.letterSpacing: Style.labelTracking
                            }

                            BlinkCaret {
                                anchors.verticalCenter: parent.verticalCenter
                                block: true
                                prompt: true
                                size: Style.font.body
                                running: root.locked && pwField.activeFocus
                            }

                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Style.motion.base
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Style.motion.enter
                            }

                        }

                    }

                    // laid out even when empty, so a plugged key or a cue never moves the clock
                    Text {
                        id: keyStatusText

                        anchors.horizontalCenter: parent.horizontalCenter
                        height: keyStatusMetrics.height
                        textFormat: Text.PlainText
                        text: root.keyStatus
                        opacity: root.keyStatus !== "" ? Style.emphasis.dim : 0
                        color: root.keyNote !== "" ? Colors.urgent : Colors.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption

                        FontMetrics {
                            id: keyStatusMetrics

                            font: keyStatusText.font
                        }

                    }

                    KeyHints {
                        anchors.horizontalCenter: parent.horizontalCenter
                        opacity: root.keyDevice !== "" || root.keyMode ? 1 : 0
                        hints: root.keyMode ? [["ENTER", "unlock"], ["ESC", "password"]] : [["CTRL+K", "security key"]]
                    }

                }

                Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: Style.spacing.lg
                    visible: surface.isPrimary
                    textFormat: Text.PlainText
                    text: root.statsText
                    color: Colors.foreground
                    opacity: Style.emphasis.faint
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                }

                // dock: how many arrived while locked and the last few apps, never their content
                Column {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Style.spacing.lg
                    visible: surface.isPrimary && root.notes.length > 0
                    spacing: Style.spacing.xxs

                    HudTitle {
                        anchors.right: parent.right
                        text: "notifications"
                        suffix: "[" + root.notes.length + "]"
                        blinking: false
                    }

                    Repeater {
                        model: root.notes.slice(0, root.notesShown)

                        Text {
                            required property var modelData

                            anchors.right: parent.right
                            textFormat: Text.PlainText
                            text: (modelData.app || "--") + " :: " + Qt.formatDateTime(new Date(modelData.timestamp), "HH:mm")
                            color: Colors.foreground
                            opacity: Style.emphasis.dim
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                        }

                    }

                }

                HudFrame {
                }

                Scanlines {
                }

            }

            // one glitch as the lock comes up and one on the way out
            Glitch {
                id: glitch

                anchors.fill: parent
                source: lockContent
            }

            Connections {
                function onGlitchOut() {
                    glitch.play();
                }

                target: root
            }

        }

    }

}
