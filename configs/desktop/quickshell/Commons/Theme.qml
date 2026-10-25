import QtQuick
import Quickshell
import Quickshell.Io
import "Palette.js" as Palette
pragma Singleton

QtObject {
    id: root

    readonly property string path: Quickshell.shellDir + "/theme.json"
    // the font is a theme input beside the palette (configs/core/wallust/font.nu), set by a theme or toggle-font
    readonly property string fontPath: Quickshell.env("HOME") + "/.cache/wal/font.json"
    property string fontFamily: "Kode Mono"
    property int fontSize: 13
    // the clamps are palette.nu's, through Palette.js's generated block; theme.json may override them
    property real backgroundValueMin: Palette.BG_VALUE_MIN
    property real backgroundValueMax: Palette.BG_VALUE_MAX
    property real lightLuminance: Palette.LIGHT_LUMINANCE
    property real foregroundContrast: 7
    property real accentMinSaturation: 0.7
    property real accentMinValue: 0.62
    property real accentContrast: 3
    property real urgentMinSaturation: 0.55
    property real urgentMinValue: 0.55
    property real urgentContrast: 3
    property real mutedContrast: 1.9
    property int paletteTransitionMs: 600
    property real glowStrength: 0.55
    property real scanlineOpacity: 0.06
    property int scanlineSpacing: 3
    property real phosphorBias: 0
    property bool cornerBrackets: true
    property real crtFlicker: 0.02
    property real matrixRain: 0.5
    property int revision: 0
    readonly property int reloadDelayMs: 80
    property FileView file
    property FileView fontFile
    property Timer reloadTimer

    file: FileView {
        path: root.path
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.apply(text());
            Util.rearmWatch(this);
        }
        onFileChanged: root.reloadTimer.restart()
    }

    fontFile: FileView {
        path: root.fontPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.applyFont(text());
            Util.rearmWatch(this);
        }
        onFileChanged: root.reloadTimer.restart()
    }

    reloadTimer: Timer {
        interval: root.reloadDelayMs
        onTriggered: {
            root.file.reload();
            root.fontFile.reload();
        }
    }

    function _num(value, fallback, min, max) {
        var n = Number(value);
        if (!isFinite(n))
            return fallback;

        return Math.max(min, Math.min(max, n));
    }

    function applyFont(raw) {
        var font;
        try {
            font = JSON.parse(raw || "{}");
        } catch (e) {
            return ;
        }
        if (typeof font.family === "string" && font.family.trim().length > 0)
            fontFamily = font.family.trim();

        if (font.size !== undefined)
            fontSize = Math.round(_num(font.size, fontSize, 6, 32));

        revision++;
    }

    function apply(raw) {
        if (!String(raw || "").trim())
            return ;

        var parsed;
        try {
            parsed = JSON.parse(raw || "{}");
        } catch (e) {
            console.warn("theme.json parse failed, keeping previous theme:", e);
            return ;
        }
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
            console.warn("theme.json is not an object, keeping previous theme");
            return ;
        }
        var p = parsed.palette || {
        };
        backgroundValueMin = _num(p.backgroundValueMin, Palette.BG_VALUE_MIN, 0, 1);
        backgroundValueMax = Math.max(backgroundValueMin, _num(p.backgroundValueMax, Palette.BG_VALUE_MAX, 0, 1));
        lightLuminance = _num(p.lightLuminance, Palette.LIGHT_LUMINANCE, 0, 1);
        foregroundContrast = _num(p.foregroundContrast, foregroundContrast, 1, 21);
        accentMinSaturation = _num(p.accentMinSaturation, accentMinSaturation, 0, 1);
        accentMinValue = _num(p.accentMinValue, accentMinValue, 0, 1);
        accentContrast = _num(p.accentContrast, accentContrast, 1, 21);
        urgentMinSaturation = _num(p.urgentMinSaturation, urgentMinSaturation, 0, 1);
        urgentMinValue = _num(p.urgentMinValue, urgentMinValue, 0, 1);
        urgentContrast = _num(p.urgentContrast, urgentContrast, 1, 21);
        mutedContrast = _num(p.mutedContrast, mutedContrast, 1, 21);
        paletteTransitionMs = Math.round(_num(p.transitionMs, paletteTransitionMs, 0, 5000));
        var fx = parsed.fx || {
        };
        glowStrength = _num(fx.glowStrength, glowStrength, 0, 1);
        scanlineOpacity = _num(fx.scanlineOpacity, scanlineOpacity, 0, 0.3);
        scanlineSpacing = Math.round(_num(fx.scanlineSpacing, scanlineSpacing, 2, 8));
        phosphorBias = _num(fx.phosphorBias, phosphorBias, 0, 1);
        cornerBrackets = (fx.cornerBrackets === undefined) ? cornerBrackets : !!fx.cornerBrackets;
        crtFlicker = _num(fx.crtFlicker, crtFlicker, 0, 0.1);
        matrixRain = _num(fx.matrixRain, matrixRain, 0, 1);
        revision++;
    }

}
