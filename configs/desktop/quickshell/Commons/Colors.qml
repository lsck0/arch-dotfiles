import QtQuick
import Quickshell
import Quickshell.Io
import "Palette.js" as Palette
pragma Singleton
pragma ComponentBehavior: Bound

QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string colorsPath: home + "/.cache/wal/colors.json"
    property color foreground: "#bfbdb6"
    property color background: "#0b0e14"
    property color accent: "#39bae6"
    property color accent2: "#ffb454"
    property color urgent: "#f07178"
    property color muted: "#565b66"
    readonly property color surface: surfaceOf(background, surfaceLift)
    readonly property real surfaceLift: 0.04
    readonly property real semanticTint: 0.15
    // conditioned as urgent is: a fixed yellow or green is unreadable on a light background
    readonly property color warn: readable(Qt.tint(warnBase, Util.alpha(accent, semanticTint)))
    readonly property color ok: readable(Qt.tint(okBase, Util.alpha(accent, semanticTint)))
    readonly property color severe: readable(Qt.tint(severeBase, Util.alpha(accent, semanticTint)))
    readonly property color warnBase: "#e8c317"
    readonly property color okBase: "#23a55a"
    readonly property color severeBase: "#e67e22"
    readonly property var rampStops: [0, 0.5, 0.75, 1]
    readonly property real urgentMinApart: 40
    readonly property real urgentMaxTurn: 20
    readonly property real accent2Contrast: 3
    property bool animatePalette: false
    component SemanticTokens: QtObject {
        id: semanticColors

        property color live: "#c0392b"
        property color recording: root.severeBase
        property color warn: root.warn
        property color speaking: root.okBase
        // meteoalarm levels 4 and 3, level 2 is warn
        property color alertRed: semanticColors.live
        property color alertOrange: semanticColors.recording
    }
    readonly property SemanticTokens semantic: SemanticTokens {}

    readonly property color scrim: Util.alpha(root.background, Style.translucency.scrim)
    readonly property color panelFill: Util.alpha(root.background, Style.translucency.panel)
    readonly property color overlayFill: Util.alpha(root.background, Style.translucency.overlay)
    component BarTokens: QtObject {
        property color background: Util.alpha(root.background, Style.translucency.bar)
        property color text: root.foreground
        property color active: root.urgent
    }
    readonly property BarTokens bar: BarTokens {}

    component PopupTokens: QtObject {
        property color text: root.foreground
        property color border: Util.alpha(root.accent, 1)
    }
    readonly property PopupTokens popups: PopupTokens {}

    component TooltipTokens: QtObject {
        property color background: root.overlayFill
        property color text: root.foreground
        property color border: Util.alpha(root.foreground, 1)
    }
    readonly property TooltipTokens tooltip: TooltipTokens {}

    component NotificationTokens: QtObject {
        property color background: root.overlayFill
        property color text: root.foreground
        property color border: Util.alpha(root.accent, 1)
    }
    readonly property NotificationTokens notifications: NotificationTokens {}

    component MenuTokens: QtObject {
        property color background: root.panelFill
        property color text: root.foreground
        property color border: Util.alpha(root.foreground, 1)
        property color scrim: root.scrim
        property color selectedBackground: Util.alpha(root.accent, Style.selectedFillAlpha)
        property color selectedText: root.accent
    }
    readonly property MenuTokens menu: MenuTokens {}

    component ImagePickerTokens: QtObject {
        property color scrim: root.scrim
        property color text: root.foreground
        property color selectedBorder: Util.alpha(root.accent, 1)
        property color unselectedBorder: Util.alpha(root.foreground, 0.28)
    }
    readonly property ImagePickerTokens imagePicker: ImagePickerTokens {}

    property string rawColors: ""
    // Background.qml holds a new palette until its wedge passes centre, released after syncHoldMaxMs
    property bool syncHold: false
    property var pendingPalette: null
    readonly property int syncHoldMaxMs: 3000
    property Timer holdTimer

    holdTimer: Timer {
        interval: root.syncHoldMaxMs
        onTriggered: root.syncHold = false
    }

    property Connections themeWatch

    themeWatch: Connections {
        function onRevisionChanged() {
            if (root.rawColors)
                root.applyColors(undefined);

        }

        target: Theme
    }

    property FileView colorsFile

    colorsFile: FileView {
        id: colorsFile

        path: root.colorsPath
        watchChanges: true
        printErrors: false
        // rearm in case the file is replaced rather than written in place
        onLoaded: {
            root.applyColors(text());
            Util.rearmWatch(this);
        }
        onFileChanged: reload()
    }

    signal paletteSynced(var p)

    function ramp(t) {
        var stops = [accent, warn, severe, urgent];
        var x = Math.max(0, Math.min(1, Number(t) || 0));
        for (let i = 1; i < rampStops.length; i++) {
            if (x <= rampStops[i]) {
                const f = (x - rampStops[i - 1]) / (rampStops[i] - rampStops[i - 1]);
                const a = stops[i - 1], b = stops[i];
                return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, 1);
            }
        }
        return urgent;
    }

    function readable(c) {
        var out = Palette.readableOn([background.r, background.g, background.b], [c.r, c.g, c.b], Theme.urgentContrast);
        return Qt.rgba(out[0], out[1], out[2], 1);
    }

    function surfaceOf(bg, amount) {
        return Qt.color(Palette.rgbToHex(Palette.shade([bg.r, bg.g, bg.b], amount, Theme.lightLuminance), "#"));
    }

    function conditionPalette(raw, fallback) {
        var parsed = typeof raw === "string" ? JSON.parse(raw || "{}") : (raw || {
        });
        var f = fallback || root;
        var hex = {
        };
        for (const role of ["background", "foreground", "accent", "accent2", "urgent", "muted"]) hex[role] = Palette.rgbToHex([f[role].r, f[role].g, f[role].b], "#")
        var p = Palette.conditionPalette(parsed, hex, {
            "backgroundValueMin": Theme.backgroundValueMin,
            "backgroundValueMax": Theme.backgroundValueMax,
            "lightLuminance": Theme.lightLuminance,
            "foregroundContrast": Theme.foregroundContrast,
            "accentMinSaturation": Theme.accentMinSaturation,
            "accentMinValue": Theme.accentMinValue,
            "accentContrast": Theme.accentContrast,
            "urgentMinSaturation": Theme.urgentMinSaturation,
            "urgentMinValue": Theme.urgentMinValue,
            "urgentContrast": Theme.urgentContrast,
            "mutedContrast": Theme.mutedContrast,
            "phosphorBias": Theme.phosphorBias,
            "accent2Contrast": root.accent2Contrast,
            "urgentMinApart": root.urgentMinApart,
            "urgentMaxTurn": root.urgentMaxTurn,
            "surfaceLift": root.surfaceLift
        });
        var out = {
            "verdict": p.verdict
        };
        for (const role of ["background", "foreground", "accent", "accent2", "urgent", "muted", "surface"]) out[role] = Qt.color(p[role])
        return out;
    }

    function assign(p, announce) {
        var changed = !Qt.colorEqual(p.background, background) || !Qt.colorEqual(p.accent, accent);
        background = p.background;
        foreground = p.foreground;
        accent = p.accent;
        accent2 = p.accent2;
        urgent = p.urgent;
        muted = p.muted;
        if (announce && changed)
            paletteSynced(p);

    }

    function applyColors(raw) {
        var fromFile = raw !== undefined;
        var source = fromFile ? (raw || "") : rawColors;

        try {
            const p = conditionPalette(source);
            // only once it parsed: a torn wallust write would otherwise poison every later re-parse
            if (fromFile)
                rawColors = source;

            if (fromFile && root.animatePalette && root.syncHold) {
                pendingPalette = p;
                return ;
            }
            assign(p, fromFile && root.animatePalette);
            if (!root.animatePalette)
                Qt.callLater(function() {
                root.animatePalette = true;
            });

        } catch (e) {
            console.warn("colors.json parse failed:", e);
        }
    }

    onSyncHoldChanged: {
        if (syncHold) {
            holdTimer.restart();
            return ;
        }
        holdTimer.stop();
        if (!pendingPalette)
            return ;

        var p = pendingPalette;
        pendingPalette = null;
        assign(p, true);
    }

    Behavior on foreground {
        enabled: root.animatePalette && !Power.saver

        ColorAnimation {
            duration: Theme.paletteTransitionMs
            easing.type: Easing.InOutQuad
        }

    }

    Behavior on background {
        enabled: root.animatePalette && !Power.saver

        ColorAnimation {
            duration: Theme.paletteTransitionMs
            easing.type: Easing.InOutQuad
        }

    }

    Behavior on accent {
        enabled: root.animatePalette && !Power.saver

        ColorAnimation {
            duration: Theme.paletteTransitionMs
            easing.type: Easing.InOutQuad
        }

    }

    Behavior on accent2 {
        enabled: root.animatePalette && !Power.saver

        ColorAnimation {
            duration: Theme.paletteTransitionMs
            easing.type: Easing.InOutQuad
        }

    }

    Behavior on urgent {
        enabled: root.animatePalette && !Power.saver

        ColorAnimation {
            duration: Theme.paletteTransitionMs
            easing.type: Easing.InOutQuad
        }

    }

    Behavior on muted {
        enabled: root.animatePalette && !Power.saver

        ColorAnimation {
            duration: Theme.paletteTransitionMs
            easing.type: Easing.InOutQuad
        }

    }

}
