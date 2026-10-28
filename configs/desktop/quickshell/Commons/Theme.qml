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
    // code defaults for every knob: property inits and apply()'s missing-key fallback both read these, so deleting a
    // key from theme.json returns to the default instead of keeping the last override. The clamps default to
    // palette.nu's values from Palette.js.
    readonly property real foregroundContrastDefault: 7
    readonly property real accentMinSaturationDefault: 0.7
    readonly property real accentMinValueDefault: 0.62
    readonly property real accentContrastDefault: 3
    readonly property real urgentMinSaturationDefault: 0.55
    readonly property real urgentMinValueDefault: 0.55
    readonly property real urgentContrastDefault: 3
    readonly property real mutedContrastDefault: 1.9
    readonly property int paletteTransitionMsDefault: 600
    readonly property real glowStrengthDefault: 0.55
    readonly property real scanlineOpacityDefault: 0.06
    readonly property int scanlineSpacingDefault: 3
    readonly property real phosphorBiasDefault: 0
    readonly property bool cornerBracketsDefault: true
    readonly property real crtFlickerDefault: 0.02
    readonly property real matrixRainDefault: 0.5
    property real backgroundValueMin: Palette.BG_VALUE_MIN
    property real backgroundValueMax: Palette.BG_VALUE_MAX
    property real lightLuminance: Palette.LIGHT_LUMINANCE
    property real foregroundContrast: foregroundContrastDefault
    property real accentMinSaturation: accentMinSaturationDefault
    property real accentMinValue: accentMinValueDefault
    property real accentContrast: accentContrastDefault
    property real urgentMinSaturation: urgentMinSaturationDefault
    property real urgentMinValue: urgentMinValueDefault
    property real urgentContrast: urgentContrastDefault
    property real mutedContrast: mutedContrastDefault
    property int paletteTransitionMs: paletteTransitionMsDefault
    property real glowStrength: glowStrengthDefault
    property real scanlineOpacity: scanlineOpacityDefault
    property int scanlineSpacing: scanlineSpacingDefault
    property real phosphorBias: phosphorBiasDefault
    property bool cornerBrackets: cornerBracketsDefault
    property real crtFlicker: crtFlickerDefault
    property real matrixRain: matrixRainDefault
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
        foregroundContrast = _num(p.foregroundContrast, foregroundContrastDefault, 1, 21);
        accentMinSaturation = _num(p.accentMinSaturation, accentMinSaturationDefault, 0, 1);
        accentMinValue = _num(p.accentMinValue, accentMinValueDefault, 0, 1);
        accentContrast = _num(p.accentContrast, accentContrastDefault, 1, 21);
        urgentMinSaturation = _num(p.urgentMinSaturation, urgentMinSaturationDefault, 0, 1);
        urgentMinValue = _num(p.urgentMinValue, urgentMinValueDefault, 0, 1);
        urgentContrast = _num(p.urgentContrast, urgentContrastDefault, 1, 21);
        mutedContrast = _num(p.mutedContrast, mutedContrastDefault, 1, 21);
        paletteTransitionMs = Math.round(_num(p.transitionMs, paletteTransitionMsDefault, 0, 5000));
        var fx = parsed.fx || {
        };
        glowStrength = _num(fx.glowStrength, glowStrengthDefault, 0, 1);
        scanlineOpacity = _num(fx.scanlineOpacity, scanlineOpacityDefault, 0, 0.3);
        scanlineSpacing = Math.round(_num(fx.scanlineSpacing, scanlineSpacingDefault, 2, 8));
        phosphorBias = _num(fx.phosphorBias, phosphorBiasDefault, 0, 1);
        cornerBrackets = (fx.cornerBrackets === undefined) ? cornerBracketsDefault : !!fx.cornerBrackets;
        crtFlicker = _num(fx.crtFlicker, crtFlickerDefault, 0, 0.1);
        matrixRain = _num(fx.matrixRain, matrixRainDefault, 0, 1);
        revision++;
    }

}
