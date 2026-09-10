#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# The one place the UI font is set, for EVERY app on the system — terminal,
# editors, the quickshell bar, and (since 2026-09-04) GTK and Qt/KDE, which
# is what actually covers "all apps": file managers, browsers' chrome, dialogs,
# system settings. Before this they were edited by `sed` calls embedded in
# Display.qml — a QML widget reaching into dotfiles, which is exactly what the
# SPEC's "make sure settings that require changes in dotfiles are properly
# done and not just hacked together" rules out.
#
# TWO SIZES, deliberately. The terminal/editor size (`size` / `set-size`) is
# 16 here; the desktop UI size (`ui-size` / `set-ui-size`) is 10. Tying them
# together would jump every GTK dialog and Qt menu to a 16pt font the first
# time the terminal size changed. The FAMILY is shared by everything; only the
# size is per-class.
#
# Not a toggle_main on/off toggle: this is a value-carrying setting with 4174
# possible values. Follows toggle-powermode.sh's shape instead — its own
# get/label/set actions — since that is this repo's existing precedent for a
# non-binary setting.
#
# Edits the REPO files, not the ~/.config paths. Both resolve to the same
# bytes (every one of these is reached through a *directory* symlink), but
# naming the repo path makes it obvious that this is a tracked change.
#
# Worth knowing: `sed -i` replaces the file's inode. That is safe here
# because these are regular files inside symlinked directories — but it
# would DESTROY a file-level symlink. `~/.config/kdeglobals` is exactly that
# case, which is why scripts/generate-kde-theme.sh uses kwriteconfig6
# instead. Check which shape a target is before adding one here.
#
# quickshell's theme.json IS reached through a file-level symlink
# (~/.config/quickshell/theme.json -> this repo), but it is still safe for the
# same reason: this script writes the repo path, so the inode replaced is the
# symlink's target, not the link.

REPO="$HOME/projects/arch-dotfiles"

GHOSTTY="$REPO/configs/ghostty/config"
ZED="$REPO/configs/zed/settings.json"
EMACS="$REPO/configs/emacs/early-init.el"
DISCORD="$REPO/configs/discord/wal.theme.css"
NVIM="$REPO/configs/nvim/lua/options.lua"
QUICKSHELL_THEME="$REPO/configs/quickshell/theme.json"

# GTK's settings.ini pair is NOT tracked in this repo (no configs/gtk*): it is
# generated into ~/.config by scripts/switch-wallpaper.sh, so these are the
# real paths rather than repo ones.
GTK_DIRS=("$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0")

# Every kdeglobals key that carries a font. Group:key pairs, driven through
# kreadconfig6/kwriteconfig6 rather than sed — ~/.config/kdeglobals is a
# FILE-level symlink into this repo, and `sed -i` would replace the inode and
# destroy the link (see the note at the top of this file).
KDE_FONT_KEYS=(
    "General:font"
    "General:fixed"
    "General:menuFont"
    "General:smallestReadableFont"
    "General:toolBarFont"
    "WM:activeFont"
)

# Cycled by `toggle`, so the setting stays usable from menu.sh and a keybind.
# Filtered to what is actually installed at runtime. The panel offers all
# 4174 families; this is the short list worth flipping between blind.
SHORTLIST=(
    "0xProto Nerd Font"
    "JetBrainsMono Nerd Font"
    "FiraCode Nerd Font"
    "Hack Nerd Font"
    "CaskaydiaCove Nerd Font"
    "CommitMono Nerd Font"
)

# ghostty is the reference for both values: it is the only target whose
# format is a single unambiguous line for each.
current_family() {
    sed -n 's/^font-family = //p' "$GHOSTTY" | head -1
}
current_size() {
    sed -n 's/^font-size = //p' "$GHOSTTY" | head -1
}

# The desktop UI size, kept separately from the terminal size. gsettings is
# the reference because it is a single unambiguous "Family Size" string.
current_ui_size() {
    local v
    v=$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null | tr -d "'")
    v=${v##* }
    [[ $v =~ ^[0-9]+$ ]] && echo "$v" || echo 10
}

installed_families() {
    fc-list : family 2>/dev/null | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' | sort -u
}

# NOT `installed_families | grep -qxF "$1"`. Under `set -o pipefail` that
# reports failure for a font that IS installed: `grep -q` exits as soon as it
# matches, the upstream `fc-list`/`sort` then dies of SIGPIPE, and pipefail
# propagates that non-zero status. Symptom was `set` refusing every family.
is_installed() {
    local list
    list=$(installed_families)
    grep -qxF "$1" <<<"$list"
}

# sed replacement text must not contain an unescaped delimiter or a `&`.
esc() { printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'; }

# quickshell's theme.json, edited as JSON rather than by sed. It is a real
# config file with a `_comment` block, and a regex that happened to also match
# a line of that prose would corrupt it silently. jq round-trips the whole
# document, so unrelated keys and the comments survive untouched.
#
# The value arrives via --arg, never interpolated into the filter, so a family
# name containing quotes or backslashes cannot break out of the expression.
#
# Written to a temp file and moved into place: an in-place edit that failed
# half-way would leave the shell watching a truncated file and fall back to
# every default at once.
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

# GTK 3/4. Two consumers, both needed: apps that read settings.ini directly
# (that is why nwg-look used to be a manual step) and apps that go through
# gsettings/the xdg portal. Each target keeps its OWN size — only the family
# is rewritten — so this cannot drag the desktop UI to the terminal's size.
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

# Qt/KDE. A kdeglobals font value is a comma-separated Qt font string whose
# FIRST field is the family and second the point size; the remaining 17 fields
# are weight/style/hinting flags that must survive untouched. Rewrite field 1
# only, per key, so smallestReadableFont keeps its 8 while the rest keep 10.
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

    sed -i "s|^font-family = .*|font-family = $e|" "$GHOSTTY"

    # All THREE zed key pairs. The version of this that lived in Display.qml
    # only handled buffer_* and ui_*, silently missing the terminal block's
    # own "font_family" — the bare key is safe to match because the opening
    # quote means it cannot also match "buffer_font_family".
    sed -i -e "s|\"buffer_font_family\": \"[^\"]*\"|\"buffer_font_family\": \"$e\"|" \
           -e "s|\"ui_font_family\": \"[^\"]*\"|\"ui_font_family\": \"$e\"|" \
           -e "s|\"font_family\": \"[^\"]*\"|\"font_family\": \"$e\"|" "$ZED"

    sed -i "s|^(defvar my/font-family \".*\")|(defvar my/font-family \"$e\")|" "$EMACS"
    sed -i "s|^  --font: \".*\";|  --font: \"$e\";|" "$DISCORD"
    sed -i "s|^set.guifont = \".*:h\([0-9]*\)\"|set.guifont = \"$e:h\1\"|" "$NVIM"

    # quickshell reads theme.json, which it live-watches — no restart, and
    # no sed into a .qml source. The UI family only: the icon family is
    # pinned to a Nerd Font in Commons/Style.qml and is deliberately not
    # representable here, because pointing it elsewhere does not blank the
    # glyphs, it silently draws different ones.
    quickshell_theme_set '.font.family = $v' "$fam"

    # The two that actually make this "all apps" rather than "all terminals".
    apply_family_gtk "$fam"
    apply_family_kde "$fam"
}

# The desktop UI size, applied to GTK and Qt/KDE only. Separate from
# `apply_size` on purpose — see the two-sizes note at the top of this file.
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
        # smallestReadableFont sits 2pt below the body font; keep that offset
        # rather than flattening every key to one number.
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
    # This used to be skipped because Style.qml carried a frozen ladder of
    # absolute pixel sizes tuned to a 30px bar, so writing an editor's font
    # size into it meant nothing. Style.qml now derives type, spacing, panel
    # widths and the bar grid from theme.json's font.size, so the number
    # finally means the same thing it means in an editor.
    quickshell_theme_set '.font.size = ($v | tonumber)' "$size"
}

# Most of these only read their config at startup. ghostty is nudged the same
# way switch-wallpaper.sh nudges it; the rest are honest about needing a
# restart rather than pretending the change is live.
#
# The gtk-theme round-trip is the standard nudge that makes running GTK apps
# re-read the font without a restart: setting the theme to "" and back forces
# a settings-changed broadcast, which a plain font-name write does not always
# trigger. Copied from switch-wallpaper.sh, which already does this for colors.
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
         "emacs/nvim/zed/discord: restart to pick this up" >&2
}

usage() {
    echo "usage: $(basename "$0") {get|size|ui-size|label|list|toggle|set <family>|set-size <n>|set-ui-size <n>}" >&2
}

case "${1:-label}" in
get) current_family ;;
size) current_size ;;
ui-size) current_ui_size ;;
label) echo "󰛖 Font: $(current_family) $(current_size)" ;;
list) installed_families ;;
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
    # Floor at 6: smallestReadableFont is derived as size-2, and a desktop
    # asking Qt for a 2pt font is a way to make the settings UI unusable.
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
