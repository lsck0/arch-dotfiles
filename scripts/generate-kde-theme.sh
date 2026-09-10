#!/usr/bin/env bash
# Regenerates KDE/Qt theming from pywal, and points Plasma's own wallpaper at
# the current image. Called from switch-wallpaper.sh's set_wallpaper(), same
# place every other themed app gets updated.
#
# Why this exists: configs/uwsm/env exported QT_QPA_PLATFORMTHEME=qt5ct while
# qt5ct was never installed, so Qt apps silently fell back to their built-in
# default and were completely unthemed while GTK apps followed pywal. That env
# var now says "kde", which resolves to KDEPlasmaPlatformTheme6.so from
# plasma-integration and reads ~/.config/kdeglobals — this script is what keeps
# those colours in sync with the wallpaper.
#
# kwriteconfig6 is used rather than sed because ~/.config/kdeglobals and
# ~/.config/plasma-org.kde.plasma.desktop-appletsrc are *file* symlinks into
# this repo. `sed -i` would replace the file and destroy the symlink;
# kwriteconfig6 was verified to write through it and leave the link intact.
set -euo pipefail

COLORS_JSON="$HOME/.cache/wal/colors.json"
KDEGLOBALS="$HOME/.config/kdeglobals"
APPLETSRC="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

[[ -f "$COLORS_JSON" ]] || exit 0
command -v kwriteconfig6 >/dev/null || exit 0

# pywal hex (#rrggbb) -> the "R,G,B" decimal triplet KDE colour keys want.
rgb() {
    local hex="${1#\#}"
    printf '%d,%d,%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

j() { jq -r "$1" "$COLORS_JSON"; }

bg=$(rgb "$(j '.special.background')")
fg=$(rgb "$(j '.special.foreground')")

c0=$(rgb "$(j '.colors.color0')")
c1=$(rgb "$(j '.colors.color1')")
c2=$(rgb "$(j '.colors.color2')")
c3=$(rgb "$(j '.colors.color3')")
c4=$(rgb "$(j '.colors.color4')")
c5=$(rgb "$(j '.colors.color5')")
c6=$(rgb "$(j '.colors.color6')")
c7=$(rgb "$(j '.colors.color7')")
c8=$(rgb "$(j '.colors.color8')")

# accent drives focus/hover/selection everywhere, matching how the quickshell
# bar uses Color.accent from the same palette.
accent="$c4"

# Semantic colours stay FIXED and are deliberately not taken from the palette.
# KDE uses these for error / warning / success text, and a pywal palette has no
# concept of "red means error" — on a brown wallpaper, error text came out
# brown and success came out orange, which loses the only information those
# colours carry. These are KDE's own defaults, i.e. what this file held before
# the generator existed.
negative="218,68,83"
neutral="246,116,0"
positive="39,174,96"

# Write one KDE colour set. KDE reads these twelve keys per [Colors:*] group;
# omitting any makes it fall back to the built-in scheme for that key only,
# which produces the half-themed look this is meant to avoid.
write_set() {
    local group="$1" bgnormal="$2" bgalt="$3" fgnormal="$4" fginactive="$5"
    kwriteconfig6 --file "$KDEGLOBALS" --group "$group" --key BackgroundNormal "$bgnormal"
    kwriteconfig6 --file "$KDEGLOBALS" --group "$group" --key BackgroundAlternate "$bgalt"
    kwriteconfig6 --file "$KDEGLOBALS" --group "$group" --key ForegroundNormal "$fgnormal"
    kwriteconfig6 --file "$KDEGLOBALS" --group "$group" --key ForegroundInactive "$fginactive"
    kwriteconfig6 --file "$KDEGLOBALS" --group "$group" --key ForegroundActive "$accent"
    kwriteconfig6 --file "$KDEGLOBALS" --group "$group" --key DecorationFocus "$accent"
    kwriteconfig6 --file "$KDEGLOBALS" --group "$group" --key DecorationHover "$accent"
    kwriteconfig6 --file "$KDEGLOBALS" --group "$group" --key ForegroundLink "$c6"
    kwriteconfig6 --file "$KDEGLOBALS" --group "$group" --key ForegroundVisited "$c5"
    kwriteconfig6 --file "$KDEGLOBALS" --group "$group" --key ForegroundNegative "$negative"
    kwriteconfig6 --file "$KDEGLOBALS" --group "$group" --key ForegroundNeutral "$neutral"
    kwriteconfig6 --file "$KDEGLOBALS" --group "$group" --key ForegroundPositive "$positive"
}

# color8 (bright black) is the dimmed-text colour. Deliberately NOT color7:
# pywal frequently sets color7 equal to the foreground (it does on this
# palette), which would render inactive text identically to normal text.
inactive="$c8"

write_set "Colors:Window"        "$bg" "$c0" "$fg" "$inactive"
write_set "Colors:View"          "$bg" "$c0" "$fg" "$inactive"
write_set "Colors:Button"        "$c0" "$c8" "$fg" "$inactive"
write_set "Colors:Tooltip"       "$bg" "$c0" "$fg" "$inactive"
write_set "Colors:Header"        "$c0" "$bg" "$fg" "$inactive"
write_set "Colors:Complementary" "$bg" "$c0" "$fg" "$inactive"
# Selection inverts: the accent becomes the background, so selected text needs
# the window background as its foreground to stay readable.
write_set "Colors:Selection"     "$accent" "$accent" "$bg" "$fg"

# Name the scheme so KDE's own UI doesn't claim an unrelated preset is active.
kwriteconfig6 --file "$KDEGLOBALS" --group "General" --key ColorScheme "pywal"
kwriteconfig6 --file "$KDEGLOBALS" --group "General" --key AccentColor "$accent"

# ---------------------------------------------------------------------------
# Plasma's own wallpaper.
#
# This machine runs Hyprland, so plasmashell is normally not running and
# `plasma-apply-wallpaperimage` (which drives it over D-Bus) would fail. Write
# the config directly instead, so a Plasma session started later comes up with
# the same wallpaper. If plasmashell *is* running, also apply it live.
WALLPAPER="${1:-}"
if [[ -n "$WALLPAPER" && -f "$WALLPAPER" && -f "$APPLETSRC" ]]; then
    # Every containment that uses the image wallpaper plugin gets updated —
    # there is one per screen/activity, so setting only the first leaves other
    # outputs on the old image.
    mapfile -t containments < <(
        grep -oP '^\[Containments\]\[\K[0-9]+(?=\]\[Wallpaper\]\[org\.kde\.image\]\[General\])' \
            "$APPLETSRC" 2>/dev/null | sort -u
    )
    for c in "${containments[@]}"; do
        kwriteconfig6 --file "$APPLETSRC" \
            --group Containments --group "$c" --group Wallpaper \
            --group org.kde.image --group General \
            --key Image "file://$WALLPAPER"
    done

    if pgrep -x plasmashell >/dev/null 2>&1 && command -v plasma-apply-wallpaperimage >/dev/null; then
        plasma-apply-wallpaperimage "$WALLPAPER" >/dev/null 2>&1 || true
    fi
fi
