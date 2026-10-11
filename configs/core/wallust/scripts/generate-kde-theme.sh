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

# render_set <header> <bg normal> <bg alternate> <fg normal> <fg inactive>
render_set() {
    printf '%s\n' "$1" BackgroundNormal="$2" BackgroundAlternate="$3" ForegroundNormal="$4" ForegroundInactive="$5" \
        ForegroundActive="$accent" DecorationFocus="$accent" DecorationHover="$accent" ForegroundLink="$c6" \
        ForegroundVisited="$c5" ForegroundNegative="$negative" ForegroundNeutral="$neutral" \
        ForegroundPositive="$positive" ""
}

inactive="$c8"

colors=$(
    render_set "[Colors:Window]"           "$bg"     "$c0"     "$fg"       "$inactive"
    render_set "[Colors:View]"             "$bg"     "$c0"     "$fg"       "$inactive"
    render_set "[Colors:Button]"           "$c0"     "$c8"     "$fg"       "$inactive"
    render_set "[Colors:Tooltip]"          "$bg"     "$c0"     "$fg"       "$inactive"
    render_set "[Colors:Header]"           "$c0"     "$bg"     "$fg"       "$inactive"
    render_set "[Colors:Header][Inactive]" "$c0"     "$bg"     "$inactive" "$inactive"
    render_set "[Colors:Complementary]"    "$bg"     "$c0"     "$fg"       "$inactive"
    render_set "[Colors:Selection]"        "$accent" "$accent" "$bg"       "$fg"
)

# kwin titlebar; [WM] also holds activeFont, so only these keys are replaced
wm=$(printf '%s\n' activeBackground="$bg" activeBlend="$bg" activeForeground="$fg" \
    inactiveBackground="$c0" inactiveBlend="$c0" inactiveForeground="$inactive")

SCHEME="$HOME/.local/share/color-schemes/pywal.colors"
mkdir -p "$(dirname "$SCHEME")"

# both are symlinks into the repo, so the target is swapped, not the link
for f in "$KDEGLOBALS" "$SCHEME"; do
    real=$(readlink -f "$f")
    touch "$real"
    tmp=$(mktemp)
    COLORS="$colors" WM="$wm" awk '
        /^\[/ { skip = /^\[Colors:/; group = $0 }
        group == "[WM]" && /^(active|inactive)(Background|Blend|Foreground)=/ { next }
        # dropped so the kwriteconfig6 below always rewrites the file sorted by kconfig
        group == "[General]" && /^AccentColor=/ { next }
        !skip { print }
        $0 == "[WM]" { print ENVIRON["WM"]; seen = 1 }
        END { if (!seen) print "[WM]\n" ENVIRON["WM"] "\n"; print ENVIRON["COLORS"] }
    ' "$real" > "$tmp"
    chmod --reference="$real" "$tmp"
    mv "$tmp" "$real"
    kwriteconfig6 --file "$f" --group General --key ColorScheme pywal
    kwriteconfig6 --file "$f" --group General --key AccentColor "$accent"
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
