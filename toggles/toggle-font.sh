#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# The one place the UI font is set, for EVERY app on the system — terminal, editors, the quickshell bar, and (since 2026-09-04) GTK and Qt/KDE, which is what actually covers "all apps": file managers, browsers' chrome, dialogs, system settings.

REPO="$HOME/projects/arch-dotfiles"

GHOSTTY="$REPO/configs/ghostty/config"
ZED="$REPO/configs/zed/settings.json"
EMACS="$REPO/configs/emacs/early-init.el"
DISCORD="$REPO/configs/discord/wal.theme.css"
SPOTIFY="$REPO/configs/spotify/user.css"
NVIM="$REPO/configs/nvim/lua/options.lua"
KITTY="$REPO/configs/kitty/kitty.conf"
QUTEBROWSER="$REPO/configs/qutebrowser/config.py"
QUTEBROWSER_STARTPAGE="$REPO/configs/qutebrowser/startpage.html"
HYPRLOCK="$REPO/configs/hyprland/hyprlock.conf"
QUICKSHELL_THEME="$REPO/configs/quickshell/theme.json"

# GTK's settings.ini pair is NOT tracked in this repo (no configs/gtk*): it is generated into ~/.config by scripts/switch-wallpaper.sh, so these are the real paths rather than repo ones.
GTK_DIRS=("$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0")

# Every kdeglobals key that carries a font.
KDE_FONT_KEYS=(
    "General:font"
    "General:fixed"
    "General:menuFont"
    "General:smallestReadableFont"
    "General:toolBarFont"
    "WM:activeFont"
)

# Cycled by `toggle`, so the setting stays usable from menu.sh and a keybind, and served to quickshell's Display panel by the `shortlist` action below -- the panel had its own hardcoded copy of four of these, so the keybind and the panel offered different sets of fonts for the same setting.
SHORTLIST=(
    "0xProto Nerd Font"
    "JetBrainsMono Nerd Font"
    "FiraCode Nerd Font"
    "Hack Nerd Font"
    "CaskaydiaCove Nerd Font"
    "CommitMono Nerd Font"
)

# ghostty is the reference for both values: it is the only target whose format is a single unambiguous line for each.
current_family() {
    sed -n 's/^font-family = //p' "$GHOSTTY" | head -1
}
current_size() {
    sed -n 's/^font-size = //p' "$GHOSTTY" | head -1
}

# The desktop UI size, kept separately from the terminal size.
current_ui_size() {
    local v
    v=$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null | tr -d "'")
    v=${v##* }
    [[ $v =~ ^[0-9]+$ ]] && echo "$v" || echo 10
}

installed_families() {
    fc-list : family 2>/dev/null | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' | sort -u
}

# NOT `installed_families | grep -qxF "$1"`.
is_installed() {
    local list
    list=$(installed_families)
    grep -qxF "$1" <<<"$list"
}

# sed replacement text must not contain an unescaped delimiter or a `&`.
esc() { printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'; }

# quickshell's theme.json, edited as JSON rather than by sed.
quickshell_theme_set() {
    local filter=$1 value=$2 tmp
    [[ -f "$QUICKSHELL_THEME" ]] || { echo "missing $QUICKSHELL_THEME" >&2; return 1; }
    tmp=$(mktemp)
    if jq --arg v "$value" "$filter" "$QUICKSHELL_THEME" >"$tmp"; then
        mv "$tmp" "$QUICKSHELL_THEME"
    else
        rm -f "$tmp"
        echo "failed to update $QUICKSHELL_THEME" >&2
        return 1
    fi
}

# GTK 3/4.
apply_family_gtk() {
    local fam=$1 e ini cur size
    e=$(esc "$fam")
    size=$(current_ui_size)
    for gtkdir in "${GTK_DIRS[@]}"; do
        ini="$gtkdir/settings.ini"
        [[ -f "$ini" ]] || continue
        cur=$(sed -n 's/^gtk-font-name=//p' "$ini" | head -1)
        # Trailing number is the size; keep whatever this file already had.
        local isize=${cur##* }
        [[ $isize =~ ^[0-9]+$ ]] || isize=$size
        if grep -q "^gtk-font-name=" "$ini"; then
            sed -i "s|^gtk-font-name=.*|gtk-font-name=$e $isize|" "$ini"
        else
            sed -i "/^\[Settings\]/a gtk-font-name=$e $isize" "$ini"
        fi
    done
    gsettings set org.gnome.desktop.interface font-name "$fam $size" 2>/dev/null || true
}

# Qt/KDE. A kdeglobals font value is a comma-separated Qt font string whose FIRST field is the family and second the point size; the remaining 17 fields are weight/style/hinting flags that must survive untouched. Rewrite field 1 only, per key, so smallestReadableFont keeps its 8 while the rest keep 10.
apply_family_kde() {
    local fam=$1 entry group key cur rest
    command -v kwriteconfig6 >/dev/null || return 0
    for entry in "${KDE_FONT_KEYS[@]}"; do
        group=${entry%%:*}
        key=${entry##*:}
        cur=$(kreadconfig6 --file kdeglobals --group "$group" --key "$key" 2>/dev/null) || continue
        [[ -n "$cur" ]] || continue
        rest=$(cut -d, -f2- <<<"$cur")
        kwriteconfig6 --file kdeglobals --group "$group" --key "$key" "$fam,$rest"
    done
}

apply_family() {
    local fam=$1 e
    e=$(esc "$fam")

    sed -i "0,/^font-family = /s|^font-family = .*|font-family = $e|" "$GHOSTTY"

    # All THREE zed key pairs.
    sed -i -e "s|\"buffer_font_family\": \"[^\"]*\"|\"buffer_font_family\": \"$e\"|" \
           -e "s|\"ui_font_family\": \"[^\"]*\"|\"ui_font_family\": \"$e\"|" \
           -e "s|\"font_family\": \"[^\"]*\"|\"font_family\": \"$e\"|" "$ZED"

    sed -i "s|^(defvar my/font-family \".*\")|(defvar my/font-family \"$e\")|" "$EMACS"
    sed -i "s|^  --font: \".*\";|  --font: \"$e\";|" "$DISCORD"

    # Spotify (via Spicetify's injected user.css).
    sed -i "s|font-family: \"[^\"]*\", \"Symbols Nerd Font\"|font-family: \"$e\", \"Symbols Nerd Font\"|" "$SPOTIFY"


    sed -i "s|^font_family .*|font_family $e|" "$KITTY"
    sed -i "s|^c.fonts.default_family = \".*\"|c.fonts.default_family = \"$e\"|" "$QUTEBROWSER"
    sed -i "s|font-family: \"[^\"]*\", monospace;|font-family: \"$e\", monospace;|" "$QUTEBROWSER_STARTPAGE"
    sed -i "s|^\$FONT = .*|\$FONT = $e|" "$HYPRLOCK"

    # quickshell reads theme.json, which it live-watches — no restart, and no sed into a .qml source.
    quickshell_theme_set '.font.family = $v' "$fam"

    # The two that actually make this "all apps" rather than "all terminals".
    apply_family_gtk "$fam"
    apply_family_kde "$fam"
}

# The desktop UI size, applied to GTK and Qt/KDE only.
apply_ui_size() {
    local size=$1 e entry group key cur fam rest ini this
    for gtkdir in "${GTK_DIRS[@]}"; do
        ini="$gtkdir/settings.ini"
        [[ -f "$ini" ]] || continue
        e=$(esc "$(current_family)")
        sed -i "s|^gtk-font-name=.*|gtk-font-name=$e $size|" "$ini"
    done
    gsettings set org.gnome.desktop.interface font-name "$(current_family) $size" 2>/dev/null || true

    command -v kwriteconfig6 >/dev/null || return 0
    for entry in "${KDE_FONT_KEYS[@]}"; do
        group=${entry%%:*}
        key=${entry##*:}
        cur=$(kreadconfig6 --file kdeglobals --group "$group" --key "$key" 2>/dev/null) || continue
        [[ -n "$cur" ]] || continue
        fam=$(cut -d, -f1 <<<"$cur")
        rest=$(cut -d, -f3- <<<"$cur")
        # smallestReadableFont sits 2pt below the body font; keep that offset rather than flattening every key to one number.
        this=$size
        [[ $key == smallestReadableFont ]] && this=$((size - 2))
        kwriteconfig6 --file kdeglobals --group "$group" --key "$key" "$fam,$this,$rest"
    done
}

apply_size() {
    local size=$1
    sed -i "s|^font-size = .*|font-size = $size|" "$GHOSTTY"
    sed -i -e "s|\"buffer_font_size\": [0-9.]*|\"buffer_font_size\": $size|" \
           -e "s|\"ui_font_size\": [0-9.]*|\"ui_font_size\": $size|" \
           -e "s|\"font_size\": [0-9.]*|\"font_size\": $size|" "$ZED"
    sed -i "s|^(defvar my/font-size .*)|(defvar my/font-size $size)|" "$EMACS"
    sed -i "s|^set.guifont = \"\(.*\):h[0-9]*\"|set.guifont = \"\1:h$size\"|" "$NVIM"

    # quickshell too, now that its whole scale derives from one base size.
    quickshell_theme_set '.font.size = ($v | tonumber)' "$size"
}

# Most of these only read their config at startup.
reload_hint() {
    touch "$GHOSTTY" 2>/dev/null || true
    local theme
    theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || true)
    if [[ -n "$theme" ]]; then
        gsettings set org.gnome.desktop.interface gtk-theme '' 2>/dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme "${theme//\'/}" 2>/dev/null || true
    fi
    echo "quickshell: applied live; gtk: applied live (portal apps) or on next start;" \
         "qt/kde: next app start; ghostty: reload with its own keybind;" \
         "emacs/nvim/zed/discord: restart to pick this up;" \
         "spotify: run 'spicetify apply' then restart Spotify to pick this up" >&2
}

usage() {
    echo "usage: $(basename "$0") {get|size|ui-size|label|list|shortlist|toggle|set <family>|set-size <n>|set-ui-size <n>}" >&2
}

# The families `toggle` cycles, filtered to what is installed.
shortlist() {
    local installed family
    installed=$(installed_families)
    for family in "${SHORTLIST[@]}"; do
        grep -qxF "$family" <<<"$installed" && printf '%s\n' "$family"
    done
}

case "${1:-label}" in
get) current_family ;;
size) current_size ;;
ui-size) current_ui_size ;;
label) echo "󰛖 Font: $(current_family) $(current_size)" ;;
list) installed_families ;;
shortlist) shortlist ;;
set)
    [[ $# -ge 2 ]] || { usage; exit 1; }
    shift
    fam="$*"
    if ! is_installed "$fam"; then
        echo "font family not installed: $fam" >&2
        exit 1
    fi
    apply_family "$fam"
    toggle_set font "$fam"
    toggle_notify -a Toggles "Font" "$fam"
    reload_hint
    ;;
set-size)
    [[ $# -ge 2 && $2 =~ ^[0-9]+$ && $2 -gt 0 ]] || { usage; exit 1; }
    apply_size "$2"
    toggle_notify -a Toggles "Font size" "$2"
    reload_hint
    ;;
set-ui-size)
    # Floor at 6: smallestReadableFont is derived as size-2, and a desktop asking Qt for a 2pt font is a way to make the settings UI unusable.
    [[ $# -ge 2 && $2 =~ ^[0-9]+$ && $2 -ge 6 ]] || { usage; exit 1; }
    apply_ui_size "$2"
    toggle_notify -a Toggles "UI font size" "$2"
    reload_hint
    ;;
toggle)
    # Cycle to the next installed shortlist entry after the current one.
    cur=$(current_family)
    avail=()
    for f in "${SHORTLIST[@]}"; do is_installed "$f" && avail+=("$f"); done
    [[ ${#avail[@]} -gt 0 ]] || { echo "no shortlist font installed" >&2; exit 0; }
    idx=-1
    for i in "${!avail[@]}"; do [[ "${avail[$i]}" == "$cur" ]] && idx=$i; done
    next=${avail[$(((idx + 1) % ${#avail[@]}))]}
    apply_family "$next"
    toggle_set font "$next"
    toggle_notify -a Toggles "Font" "$next"
    reload_hint
    ;;
*) usage; exit 1 ;;
esac
