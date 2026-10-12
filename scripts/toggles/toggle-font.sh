#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# the one place the ui font is set for every app: terminal, editors, quickshell bar, gtk and qt/kde

GHOSTTY="$DOTFILES/configs/desktop/ghostty/config"
ZED="$DOTFILES/configs/programming/zed/settings.json"
EMACS="$DOTFILES/configs/programming/emacs/early-init.el"
DISCORD="$DOTFILES/configs/socials/discord/wal.theme.css"
SPOTIFY="$DOTFILES/configs/socials/spotify/user.css"
KITTY="$DOTFILES/configs/desktop/kitty/kitty.conf"
QUTEBROWSER="$DOTFILES/configs/desktop/qutebrowser/config.py"
QUTEBROWSER_STARTPAGE="$DOTFILES/configs/desktop/qutebrowser/startpage.html"
# link.sh renders a per-user copy; edit it too so the font shows before the next config run
QUTEBROWSER_STARTPAGE_RENDERED="${XDG_CONFIG_HOME:-$HOME/.config}/qutebrowser/startpage.html"
QUICKSHELL_THEME="$DOTFILES/configs/desktop/quickshell/theme.json"
VSCODE="$DOTFILES/configs/programming/vscode/settings.json"
ZATHURA="$DOTFILES/configs/desktop/zathura/zathurarc"
FIREFOX_CHROME="$DOTFILES/configs/desktop/firefox/userChrome.css"
GTK_CSS="$DOTFILES/configs/desktop/gtk/gtk.css"

# gtk settings.ini is generated into ~/.config by switch-wallpaper.sh, not tracked here, so use real paths
GTK_DIRS=("$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0")

KDE_FONT_KEYS=(
    "General:font"
    "General:fixed"
    "General:menuFont"
    "General:smallestReadableFont"
    "General:toolBarFont"
    "WM:activeFont"
)

# cycled by toggle and served to quickshell's Display panel via the shortlist action, so both share one list
SHORTLIST=(
    "Kode Mono"
    "Tektur"
    "0xProto Nerd Font"
    "JetBrainsMono Nerd Font"
    "FiraCode Nerd Font"
    "Hack Nerd Font"
    "CaskaydiaCove Nerd Font"
    "CommitMono Nerd Font"
)

# family from quickshell's theme (ghostty may hold the mono cut, see mono_family); size from ghostty
current_family() {
    jq -er '.font.family' "$QUICKSHELL_THEME" 2>/dev/null || sed -n 's/^font-family = //p' "$GHOSTTY" | head -1
}
current_size() {
    sed -n 's/^font-size = //p' "$GHOSTTY" | head -1
}

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

quickshell_theme_set() {
    local filter=$1 value=$2 tmp
    [[ -f "$QUICKSHELL_THEME" ]] || { echo "missing $QUICKSHELL_THEME" >&2; return 1; }
    tmp="${QUICKSHELL_THEME}.new.$$"
    if jq --arg v "$value" "$filter" "$QUICKSHELL_THEME" >"$tmp"; then
        mv "$tmp" "$QUICKSHELL_THEME"
    else
        rm -f "$tmp"
        echo "failed to update $QUICKSHELL_THEME" >&2
        return 1
    fi
}

# GTK 3/4: write gtk-font-name=<fam> <size> in each settings.ini, setting family and/or size, keeping the other
gtk_font_rewrite() {
    local newfam=$1 newsize=$2 gtkdir ini cur size e
    for gtkdir in "${GTK_DIRS[@]}"; do
        ini="$gtkdir/settings.ini"
        [[ -f "$ini" ]] || continue
        cur=$(sed -n 's/^gtk-font-name=//p' "$ini" | head -1)
        # trailing number is the size; keep this file's own unless a new one is given
        size=${cur##* }
        [[ $size =~ ^[0-9]+$ ]] || size=$(current_ui_size)
        [[ -n "$newsize" ]] && size=$newsize
        e=$(esc "${newfam:-$(current_family)}")
        if grep -q "^gtk-font-name=" "$ini"; then
            sed -i "s|^gtk-font-name=.*|gtk-font-name=$e $size|" "$ini"
        else
            sed -i "/^\[Settings\]/a gtk-font-name=$e $size" "$ini"
        fi
    done
    gsettings set org.gnome.desktop.interface font-name "${newfam:-$(current_family)} ${newsize:-$(current_ui_size)}" 2>/dev/null || true
}

# qt/kde: each kdeglobals font is a comma-separated qt string (family,size,...); set field 1 and/or field 2, keep the
# rest. smallestReadableFont sits 2pt below the body font, so it tracks a size change at that offset
kde_font_rewrite() {
    local newfam=$1 newsize=$2 entry group key cur fam size rest
    command -v kwriteconfig6 >/dev/null || return 0
    for entry in "${KDE_FONT_KEYS[@]}"; do
        group=${entry%%:*}
        key=${entry##*:}
        cur=$(kreadconfig6 --file kdeglobals --group "$group" --key "$key" 2>/dev/null) || continue
        [[ -n "$cur" ]] || continue
        fam=$(cut -d, -f1 <<<"$cur")
        size=$(cut -d, -f2 <<<"$cur")
        rest=$(cut -d, -f3- <<<"$cur")
        [[ -n "$newfam" ]] && fam=$newfam
        if [[ -n "$newsize" ]]; then
            size=$newsize
            [[ $key == smallestReadableFont ]] && size=$((newsize - 2))
        fi
        kwriteconfig6 --file kdeglobals --group "$group" --key "$key" "$fam,$size,$rest"
    done
}

# Terminals and editors need fixed pitch: a proportional family maps to its monospace partner.
declare -A MONO_PARTNER=(["Tektur"]="Kode Mono")
mono_family() {
    local fam=$1 partner=${MONO_PARTNER[$1]:-}
    if [[ -n "$partner" ]] && is_installed "$partner"; then
        echo "$partner"
    else
        echo "$fam"
    fi
}

# nvim_guifont <family> <size>, either empty to keep the current one: a marker lua/options.lua reads at startup, so
# no edit lands in the tracked config
nvim_guifont() {
    local file="$TOGGLES_STATE_DIR/nvim-guifont" cur="Kode Mono:h16"
    [[ -f "$file" ]] && cur=$(<"$file")
    toggle_set nvim-guifont "${1:-${cur%:h*}}:h${2:-${cur##*:h}}"
}

apply_family() {
    local fam=$1 e m
    e=$(esc "$fam")
    m=$(esc "$(mono_family "$fam")")

    sed -i "0,/^font-family = /s|^font-family = .*|font-family = $m|" "$GHOSTTY"

    # All THREE zed key pairs; only the UI one may be proportional.
    sed -i -e "s|\"buffer_font_family\": \"[^\"]*\"|\"buffer_font_family\": \"$m\"|" \
           -e "s|\"ui_font_family\": \"[^\"]*\"|\"ui_font_family\": \"$e\"|" \
           -e "s|\"font_family\": \"[^\"]*\"|\"font_family\": \"$m\"|" "$ZED"

    sed -i "s|^(defvar my/font-family \".*\")|(defvar my/font-family \"$m\")|" "$EMACS"
    nvim_guifont "$(mono_family "$fam")" ""
    sed -i "s|^  --font: \".*\";|  --font: \"$e\";|" "$DISCORD"
    sed -i "s|font-family: \"[^\"]*\", \"Symbols Nerd Font\"|font-family: \"$e\", \"Symbols Nerd Font\"|" "$SPOTIFY"
    sed -i "s|^font_family .*|font_family $m|" "$KITTY"
    sed -i "s|^c.fonts.default_family = \".*\"|c.fonts.default_family = \"$e\"|" "$QUTEBROWSER"
    for page in "$QUTEBROWSER_STARTPAGE" "$QUTEBROWSER_STARTPAGE_RENDERED"; do
        if [[ -f "$page" && ! -L "$page" ]]; then
            sed -i "s|font-family: \"[^\"]*\", monospace;|font-family: \"$e\", monospace;|" "$page"
        fi
    done
    sed -i "s|\"editor.fontFamily\": \"'[^']*'|\"editor.fontFamily\": \"'$m'|" "$VSCODE"
    sed -i "s|^set font \"[^\"]*\\( [0-9]*\\)\"|set font \"$e\\1\"|" "$ZATHURA"
    sed -i "s|--rtk-chrome-font: \"[^\"]*\",|--rtk-chrome-font: \"$e\",|" "$FIREFOX_CHROME"
    sed -i "s|font-family: \"[^\"]*\", sans-serif;|font-family: \"$e\", sans-serif;|" "$GTK_CSS"

    # quickshell live-watches theme.json: no restart, no sed into a .qml source
    quickshell_theme_set '.font.family = $v' "$fam"

    gtk_font_rewrite "$fam" ""
    kde_font_rewrite "$fam" ""
}

apply_ui_size() {
    gtk_font_rewrite "" "$1"
    kde_font_rewrite "" "$1"
}

apply_size() {
    local size=$1
    sed -i "s|^font-size = .*|font-size = $size|" "$GHOSTTY"
    sed -i "s|^font_size .*|font_size $size|" "$KITTY"
    sed -i -e "s|\"buffer_font_size\": [0-9.]*|\"buffer_font_size\": $size|" \
           -e "s|\"ui_font_size\": [0-9.]*|\"ui_font_size\": $size|" \
           -e "s|\"font_size\": [0-9.]*|\"font_size\": $size|" "$ZED"
    sed -i "s|^(defvar my/font-size .*)|(defvar my/font-size $size)|" "$EMACS"
    nvim_guifont "" "$size"
    quickshell_theme_set '.font.size = ($v | tonumber)' "$size"
}

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
    cur=$(current_family)
    mapfile -t avail < <(shortlist)
    [[ ${#avail[@]} -gt 0 ]] || { echo "no shortlist font installed" >&2; exit 0; }
    idx=$(toggle_index_of "$cur" -1 "${avail[@]}")
    next=${avail[$(((idx + 1) % ${#avail[@]}))]}
    apply_family "$next"
    toggle_notify -a Toggles "Font" "$next"
    reload_hint
    ;;
*) usage; exit 1 ;;
esac
