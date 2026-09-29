#!/usr/bin/env bash
# kde colours from pywal; $1 sets the plasma wallpaper
set -euo pipefail

COLORS_JSON="$HOME/.cache/wal/colors.json"
KDEGLOBALS="$HOME/.config/kdeglobals"
APPLETSRC="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

[[ -f "$COLORS_JSON" ]] || exit 0
command -v kwriteconfig6 >/dev/null || exit 0

# #rrggbb -> r,g,b
rgb() {
    local hex="${1#\#}"
    printf '%d,%d,%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

j() { jq -r "$1" "$COLORS_JSON"; }

bg=$(rgb "$(j '.special.background')")
fg=$(rgb "$(j '.special.foreground')")

c0=$(rgb "$(j '.colors.color0')")
c4=$(rgb "$(j '.colors.color4')")
c5=$(rgb "$(j '.colors.color5')")
c6=$(rgb "$(j '.colors.color6')")
c8=$(rgb "$(j '.colors.color8')")

accent="$c4"

# fixed on purpose, not from the palette
negative="218,68,83"
neutral="246,116,0"
positive="39,174,96"

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

inactive="$c8"

# kwin titlebar
write_wm() {
    local file="$1"
    kwriteconfig6 --file "$file" --group WM --key activeBackground "$bg"
    kwriteconfig6 --file "$file" --group WM --key activeBlend "$bg"
    kwriteconfig6 --file "$file" --group WM --key activeForeground "$fg"
    kwriteconfig6 --file "$file" --group WM --key inactiveBackground "$c0"
    kwriteconfig6 --file "$file" --group WM --key inactiveBlend "$c0"
    kwriteconfig6 --file "$file" --group WM --key inactiveForeground "$inactive"
}

write_header_inactive() {
    local file="$1" k
    for k in BackgroundNormal:"$c0" BackgroundAlternate:"$bg" ForegroundNormal:"$inactive" \
             ForegroundInactive:"$inactive" ForegroundActive:"$accent" DecorationFocus:"$accent" \
             DecorationHover:"$accent" ForegroundLink:"$c6" ForegroundVisited:"$c5" \
             ForegroundNegative:"$negative" ForegroundNeutral:"$neutral" ForegroundPositive:"$positive"; do
        kwriteconfig6 --file "$file" --group "Colors:Header" --group Inactive --key "${k%%:*}" "${k#*:}"
    done
}

SCHEME="$HOME/.local/share/color-schemes/pywal.colors"
mkdir -p "$(dirname "$SCHEME")"

for f in "$KDEGLOBALS" "$SCHEME"; do
    write_set "$f" "Colors:Window"        "$bg" "$c0" "$fg" "$inactive"
    write_set "$f" "Colors:View"          "$bg" "$c0" "$fg" "$inactive"
    write_set "$f" "Colors:Button"        "$c0" "$c8" "$fg" "$inactive"
    write_set "$f" "Colors:Tooltip"       "$bg" "$c0" "$fg" "$inactive"
    write_set "$f" "Colors:Header"        "$c0" "$bg" "$fg" "$inactive"
    write_set "$f" "Colors:Complementary" "$bg" "$c0" "$fg" "$inactive"
    write_set "$f" "Colors:Selection"     "$accent" "$accent" "$bg" "$fg"
    write_header_inactive "$f"
    write_wm "$f"
    kwriteconfig6 --file "$f" --group "General" --key ColorScheme "pywal"
    kwriteconfig6 --file "$f" --group "General" --key AccentColor "$accent"
done

kwriteconfig6 --file "$SCHEME" --group "General" --key Name "pywal"

WALLPAPER="${1:-}"
if [[ -n "$WALLPAPER" && -f "$WALLPAPER" && -f "$APPLETSRC" ]]; then
    # one containment per screen/activity
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
