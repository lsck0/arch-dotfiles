#!/usr/bin/env bash
# Regenerates KDE/Qt theming from pywal, and points Plasma's own wallpaper at the current image.
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

# accent drives focus/hover/selection everywhere, matching how the quickshell bar uses Color.accent from the same palette.
accent="$c4"

# Semantic colours stay FIXED and are deliberately not taken from the palette.
negative="218,68,83"
neutral="246,116,0"
positive="39,174,96"

# Write one KDE colour set into the given INI file.
write_set() {
    local file="$1" group="$2" bgnormal="$3" bgalt="$4" fgnormal="$5" fginactive="$6"
    kwriteconfig6 --file "$file" --group "$group" --key BackgroundNormal "$bgnormal"
    kwriteconfig6 --file "$file" --group "$group" --key BackgroundAlternate "$bgalt"
    kwriteconfig6 --file "$file" --group "$group" --key ForegroundNormal "$fgnormal"
    kwriteconfig6 --file "$file" --group "$group" --key ForegroundInactive "$fginactive"
    kwriteconfig6 --file "$file" --group "$group" --key ForegroundActive "$accent"
    kwriteconfig6 --file "$file" --group "$group" --key DecorationFocus "$accent"
    kwriteconfig6 --file "$file" --group "$group" --key DecorationHover "$accent"
    kwriteconfig6 --file "$file" --group "$group" --key ForegroundLink "$c6"
    kwriteconfig6 --file "$file" --group "$group" --key ForegroundVisited "$c5"
    kwriteconfig6 --file "$file" --group "$group" --key ForegroundNegative "$negative"
    kwriteconfig6 --file "$file" --group "$group" --key ForegroundNeutral "$neutral"
    kwriteconfig6 --file "$file" --group "$group" --key ForegroundPositive "$positive"
}

# color8 (bright black) is the dimmed-text colour.
inactive="$c8"

# The named color-scheme file feeds Dolphin/KDE's scheme picker; regenerate it so it tracks the wallpaper instead of drifting from kdeglobals.
SCHEME="$HOME/.local/share/color-schemes/pywal.colors"
mkdir -p "$(dirname "$SCHEME")"

# Write kdeglobals (authoritative for running apps) and the scheme file from the same palette.
for f in "$KDEGLOBALS" "$SCHEME"; do
    write_set "$f" "Colors:Window"        "$bg" "$c0" "$fg" "$inactive"
    write_set "$f" "Colors:View"          "$bg" "$c0" "$fg" "$inactive"
    write_set "$f" "Colors:Button"        "$c0" "$c8" "$fg" "$inactive"
    write_set "$f" "Colors:Tooltip"       "$bg" "$c0" "$fg" "$inactive"
    write_set "$f" "Colors:Header"        "$c0" "$bg" "$fg" "$inactive"
    write_set "$f" "Colors:Complementary" "$bg" "$c0" "$fg" "$inactive"
    # Selection inverts: the accent becomes the background, so selected text needs the window background as its foreground to stay readable.
    write_set "$f" "Colors:Selection"     "$accent" "$accent" "$bg" "$fg"
    # Name the scheme so KDE's own UI doesn't claim an unrelated preset is active.
    kwriteconfig6 --file "$f" --group "General" --key ColorScheme "pywal"
    kwriteconfig6 --file "$f" --group "General" --key AccentColor "$accent"
done

# The scheme file also carries a display Name for the picker.
kwriteconfig6 --file "$SCHEME" --group "General" --key Name "pywal"

# --------------------------------------------------------------------------- Plasma's own wallpaper.
WALLPAPER="${1:-}"
if [[ -n "$WALLPAPER" && -f "$WALLPAPER" && -f "$APPLETSRC" ]]; then
    # Every containment that uses the image wallpaper plugin gets updated — there is one per screen/activity, so setting only the first leaves other outputs on the old image.
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
