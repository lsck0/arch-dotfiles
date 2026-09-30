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

# write_set <file> <bg normal> <bg alternate> <fg normal> <fg inactive> <group>...
write_set() {
    local file="$1" key group_args=()
    local keys=(BackgroundNormal:"$2" BackgroundAlternate:"$3" ForegroundNormal:"$4" ForegroundInactive:"$5"
        ForegroundActive:"$accent" DecorationFocus:"$accent" DecorationHover:"$accent" ForegroundLink:"$c6"
        ForegroundVisited:"$c5" ForegroundNegative:"$negative" ForegroundNeutral:"$neutral"
        ForegroundPositive:"$positive")
    shift 5
    for group in "$@"; do group_args+=(--group "$group"); done
    for key in "${keys[@]}"; do
        kwriteconfig6 --file "$file" "${group_args[@]}" --key "${key%%:*}" "${key#*:}"
    done
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

SCHEME="$HOME/.local/share/color-schemes/pywal.colors"
mkdir -p "$(dirname "$SCHEME")"

for f in "$KDEGLOBALS" "$SCHEME"; do
    write_set "$f" "$bg"     "$c0"     "$fg"       "$inactive" "Colors:Window"
    write_set "$f" "$bg"     "$c0"     "$fg"       "$inactive" "Colors:View"
    write_set "$f" "$c0"     "$c8"     "$fg"       "$inactive" "Colors:Button"
    write_set "$f" "$bg"     "$c0"     "$fg"       "$inactive" "Colors:Tooltip"
    write_set "$f" "$c0"     "$bg"     "$fg"       "$inactive" "Colors:Header"
    write_set "$f" "$c0"     "$bg"     "$inactive" "$inactive" "Colors:Header" Inactive
    write_set "$f" "$bg"     "$c0"     "$fg"       "$inactive" "Colors:Complementary"
    write_set "$f" "$accent" "$accent" "$bg"       "$fg"       "Colors:Selection"
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
