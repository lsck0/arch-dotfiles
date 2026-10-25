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

Item {
    id: root

    property bool locked: false
    property bool authError: false
    property string primaryScreenName: ""
    property string _pw: ""
    property var activeField: null
    property real lockedAtMs: 0
    property bool keyMode: false
    property string _pin: ""
    property string keyDevice: ""
    property int pinRetries: -1
    property int pinLengthMin: 4
    property string keyCue: ""
    property string keyNote: ""
    readonly property int keyProbeSettleMs: 250
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
    readonly property string notesDir: Paths.state + "/notifications"
    readonly property int notesShown: 3
    property var notes: []
    readonly property var player: {
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
        if (unlockDelay.running) {
            unlockDelay.stop();
            return ;
        }
        if (root.locked) {
            if (sessionLock.locked)
                return ;

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

    function unlock() {
        root.authError = false;
        root._pw = "";
        root.clearFields();
        pamPw.active = false;
        root.glitchOut();
        unlockDelay.restart();
    }

    function submit() {
        if (!root.locked || !root.activeField || root.activeField.text.length === 0 || pamPw.active)
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

        interval: Style.motion.enabled ? 180 : 0
        onTriggered: root.locked = false
    }

    IpcHandler {
        function lock() : string {
            root.lock();
            return "ok";
        }

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

    JsonProcess {
        id: notesProc

        command: ["bash", "-c", "cat \"$1\"/*.json \"$1\"/history/*.json 2>/dev/null" + " | jq -s -c --argjson since \"$2\" '[.[] | select((.timestamp // 0) >= $since)" + " | {app: (.app // \"\"), timestamp}] | unique_by([.timestamp, .app]) | sort_by(-.timestamp)'", "--", root.notesDir, String(Math.floor(root.lockedAtMs))]

        onParsed: function(parsed) {
            root.notes = Array.isArray(parsed) ? parsed : [];
        }
        onFailed: root.notes = []

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

        WlSessionLockSurface {
            id: surface

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

            Item {
                id: lockContent

                anchors.fill: parent

                Image {
                    id: wallpaper

                    anchors.fill: parent
                    source: root.locked ? Util.fileUrl(Quickshell.env("HOME") + "/.cache/wal/wallpaper") : ""
                    cache: false
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: {
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

                Rectangle {
                    anchors.fill: parent

                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: Util.alpha(Colors.background, 0.7)
                        }

                        GradientStop {
                            position: 1
                            color: Util.alpha(Colors.accent, 0.22)
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
                        color: Util.alpha(Colors.background, 0.55)
                        border.width: root.authError ? 2 : 1
                        border.color: root.authError ? Colors.urgent : (pwField.activeFocus ? Colors.accent : Style.normalBorderColor)
                        radius: Style.shape.data
                        opacity: (pwField.text.length > 0 || root.authError || pamPw.active || root.keyMode) ? 1 : 0

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
                            placeholderTextColor: root.authError ? Colors.urgent : Util.alpha(Colors.foreground, Style.emphasis.faint)
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
