import QtQuick
import Quickshell.Io
import "Palette.js" as Palette
pragma Singleton
pragma ComponentBehavior: Bound

QtObject {
    id: root

    readonly property string colorsPath: Paths.wal + "/colors.json"
    property color foreground: "#bfbdb6"
    property color background: "#0b0e14"
    property color accent: "#39bae6"
    // accent and foreground conditioned for text: readable at Theme.textContrast on background and surface
    property color accentText: "#39bae6"
    property color textDim: "#858582"
    property color accent2: "#ffb454"
    property color urgent: "#f07178"
    // urgent conditioned for text; strokes and fills keep plain urgent at its 3:1
    readonly property color urgentText: textFor(urgent)
    property color muted: "#565b66"
    readonly property color surface: surfaceOf(background, surfaceLift)
    readonly property real surfaceLift: 0.04
    readonly property real semanticTint: 0.15
    readonly property color warn: readable(Qt.tint(warnBase, Util.alpha(accent, semanticTint)))
    readonly property color ok: readable(Qt.tint(okBase, Util.alpha(accent, semanticTint)))
    readonly property color severe: readable(Qt.tint(severeBase, Util.alpha(accent, semanticTint)))
    // warn and ok conditioned for text; gauges and glyphs keep the 3:1 warn and ok
    readonly property color warnText: textFor(warn)
    readonly property color okText: textFor(ok)
    // accent2 is held at accent2Contrast for strokes and glows; this is its text form
    readonly property color accent2Text: textFor(accent2)
    readonly property color warnBase: "#e8c317"
    readonly property color okBase: "#23a55a"
    readonly property color severeBase: "#e67e22"
    readonly property var rampStops: [0, 0.5, 0.75, 1]
    readonly property real urgentMinApart: Palette.URGENT_APART_MIN_DEG
    readonly property real urgentMaxTurn: 20
    readonly property real accent2Contrast: Palette.ACCENT2_RATIO
    property bool animatePalette: false
    component SemanticTokens: QtObject {
        id: semanticColors

        property color live: "#c0392b"
        property color recording: root.severeBase
        property color warn: root.warn
        property color speaking: root.okBase
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
        property color active: root.urgentText
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
        property color selectedText: root.foreground
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
        var out = Palette.readableOn([background.r, background.g, background.b], [c.r, c.g, c.b], Theme.semanticContrast);
        return Qt.rgba(out[0], out[1], out[2], 1);
    }

    // c conditioned for text like accentText: readable at Theme.textContrast on background and surface
    function textFor(c) {
        var out = Palette.readableOnAll([[background.r, background.g, background.b], [surface.r, surface.g, surface.b]], [c.r, c.g, c.b], Theme.textContrast);
        return Qt.rgba(out[0], out[1], out[2], 1);
    }

    // c conditioned for text on a translucent fill laid over background or surface, and on those two bare
    function textOnFill(c, fill) {
        var bgs = [];
        for (const b of [background, surface]) {
            const under = [b.r, b.g, b.b];
            bgs.push(under, Palette.mix(under, [fill.r, fill.g, fill.b], fill.a));
        }
        var out = Palette.readableOnAll(bgs, [c.r, c.g, c.b], Theme.textContrast);
        return Qt.rgba(out[0], out[1], out[2], 1);
    }

    // c conditioned for text on overlayFill over any backdrop: a white or black glyph showing through is the worst case
    function textOnOverlay(c) {
        const through = 1 - Style.translucency.overlay;
        return textOnFill(textOnFill(c, Qt.rgba(1, 1, 1, through)), Qt.rgba(0, 0, 0, through));
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
            "textContrast": Theme.textContrast,
            "urgentRed": Palette.rgbToHex([root.semantic.live.r, root.semantic.live.g, root.semantic.live.b], "#"),
            "accent2Contrast": root.accent2Contrast,
            "urgentMinApart": root.urgentMinApart,
            "urgentMaxTurn": root.urgentMaxTurn,
            "surfaceLift": root.surfaceLift
        });
        var out = {
            "verdict": p.verdict
        };
        for (const role of ["background", "foreground", "accent", "accentText", "textDim", "accent2", "urgent", "muted", "surface"]) out[role] = Qt.color(p[role])
        return out;
    }

    function assign(p, announce) {
        var changed = !Qt.colorEqual(p.background, background) || !Qt.colorEqual(p.accent, accent);
        background = p.background;
        foreground = p.foreground;
        accent = p.accent;
        accentText = p.accentText;
        textDim = p.textDim;
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

    Behavior on accentText {
        enabled: root.animatePalette && !Power.saver

        ColorAnimation {
            duration: Theme.paletteTransitionMs
            easing.type: Easing.InOutQuad
        }

    }

    Behavior on textDim {
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
