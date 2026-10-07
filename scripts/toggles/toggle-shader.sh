#!/usr/bin/env bash
# Hyprland's single screen_shader slot. Grading and night light are hardware (toggle-color-grading.sh, toggle-nightlight.sh).
# Shaders are discovered: every configs/desktop/hyprland/shaders/<name>.frag is one, its `// @key value` header lines are the metadata:
#   @label, @variants a b c (entries become <name>:<variant>, VARIANT is rewritten to the index),
#   @animated (uses time, needs damage tracking off), @themed (THEME constants from the shell palette).
# Sources may `#include "x.glsl"`; the rendered copy in $XDG_RUNTIME_DIR/shaders is what Hyprland loads.
# Any active shader costs direct scanout and a full-screen pass per frame.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

SHADER_DIR="${HOME}/.config/hypr/shaders"
RENDER_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/shaders"
# damage_tracking values: 2 is hyprland's default (full), 0 redraws every frame for time-driven shaders
DAMAGE_FULL=2
DAMAGE_NONE=0

shader_names() {
    local f
    for f in "$SHADER_DIR"/*.frag; do basename "$f" .frag; done
}

shader_meta() { sed -n "s|^// @$2 \(.*\)$|\1|p" "$SHADER_DIR/$1.frag" | head -n 1; }

shader_flag() { grep -qx "// @$2" "$SHADER_DIR/$1.frag"; }

# every selectable entry: <name>, or <name>:<variant> per @variants word
entries() {
    local name variant
    local -a variants
    while IFS= read -r name; do
        read -ra variants <<<"$(shader_meta "$name" variants)"
        if ((${#variants[@]} == 0)); then
            echo "$name"
        else
            for variant in "${variants[@]}"; do echo "$name:$variant"; done
        fi
    done < <(shader_names)
}

# parse an entry against the discovered set, rejecting anything else
entry_parse() {
    local entry=$1
    local -a variants
    # a bare name with variants means its first variant
    if [[ "$entry" != *:* && -f "$SHADER_DIR/$entry.frag" ]]; then
        read -ra variants <<<"$(shader_meta "$entry" variants)"
        ((${#variants[@]} == 0)) || entry="$entry:${variants[0]}"
    fi
    # not -q: an early grep exit would SIGPIPE entries under pipefail
    entries | grep -xF -- "$entry" >/dev/null || { echo "toggle-shader: unknown shader '$1', see: $(basename "$0") list" >&2; return 1; }
    echo "$entry"
}

current() {
    local path
    path=$(hyprctl getoption decoration:screen_shader -j | jq -r '.str')
    case "$path" in
    "" | "[[EMPTY]]") echo off ;;
    "$RENDER_DIR"/*.frag)
        path=$(basename "$path" .frag)
        echo "${path/@/:}"
        ;;
    *) echo custom ;;
    esac
}

label_of() {
    local name=${1%%:*} variant=""
    [[ "$1" == *:* ]] && variant=${1#*:}
    if [[ -n "$variant" ]]; then echo "$(shader_meta "$name" label): ${variant^}"; else shader_meta "$name" label; fi
}

# theme constants from the shell palette as sed commands; nothing (template defaults) without a palette
theme_script() {
    local palette
    palette=$(timeout 3 qs ipc -p "${HOME}/.config/quickshell" call shell palette 2>/dev/null) || return 0
    jq -er '
        def float: tostring | if test("[.e]") then . else . + ".0" end;
        def vec3: "vec3(\(.[0] | float), \(.[1] | float), \(.[2] | float))";
        if [.background[], .accent[], .glowStrength, .scanlineOpacity, .scanlineSpacing] | all(type == "number")
        then . else error("bad palette") end |
        "s|^const vec3 BACKGROUND = .*|const vec3 BACKGROUND = \(.background | vec3);|",
        "s|^const vec3 ACCENT = .*|const vec3 ACCENT = \(.accent | vec3);|",
        "s|^const float GLOW = .*|const float GLOW = \(.glowStrength | float);|",
        "s|^const float SCANLINE_OPACITY = .*|const float SCANLINE_OPACITY = \(.scanlineOpacity | float);|",
        "s|^const float SCANLINE_SPACING_PX = .*|const float SCANLINE_SPACING_PX = \(.scanlineSpacing | float);|"
    ' <<<"$palette" 2>/dev/null || true
}

# write the loadable copy of an entry, print its path
render() {
    local entry=$1 name=${1%%:*} variant="" script="" index out
    local -a variants
    [[ "$entry" == *:* ]] && variant=${entry#*:}
    if [[ -n "$variant" ]]; then
        read -ra variants <<<"$(shader_meta "$name" variants)"
        for index in "${!variants[@]}"; do [[ "${variants[$index]}" == "$variant" ]] && break; done
        script="s|^const int VARIANT = .*|const int VARIANT = ${index};|"
    fi
    shader_flag "$name" themed && script+=$'\n'"$(theme_script)"
    mkdir -p "$RENDER_DIR"
    out="$RENDER_DIR/${entry/:/@}.frag"
    awk -v dir="$SHADER_DIR" '
        /^#include "[^"]+"$/ { file = dir "/" substr($2, 2, length($2) - 2); while ((getline line < file) > 0) print line; close(file); next }
        { print }
    ' "$SHADER_DIR/$name.frag" | sed "${script:-}" >"$out.tmp"
    mv "$out.tmp" "$out"
    echo "$out"
}

# hyprctl keyword rejects Lua configs
load() {
    local damage=$1 shader=$2
    hyprctl eval 'hl.config({ decoration = { screen_shader = "" } })' >/dev/null
    hyprctl eval "hl.config({ debug = { damage_tracking = ${damage} } })" >/dev/null
    hyprctl eval "hl.config({ decoration = { screen_shader = [[${shader}]] } })" >/dev/null
}

load_entry() {
    local entry=$1 damage=$DAMAGE_FULL
    shader_flag "${entry%%:*}" animated && damage=$DAMAGE_NONE
    load "$damage" "$(render "$entry")"
}

# a config reload drops the shader, so `reapply` restores this; keyed to the compositor instance so a new session never inherits it
apply() {
    local entry=$1
    if [[ "$entry" == off ]]; then
        load "$DAMAGE_FULL" ""
        toggle_set_volatile shader off
        toggle_notify -a Toggles "Shader" "Off"
        return
    fi
    load_entry "$entry"
    toggle_set_volatile shader "${HYPRLAND_INSTANCE_SIGNATURE:-} $entry"
    toggle_set shader-last "$entry"
    toggle_notify -a Toggles "Shader" "$(label_of "$entry")"
}

status_json() {
    local name
    while IFS= read -r name; do
        jq -nc --arg name "$name" --arg label "$(shader_meta "$name" label)" \
            --arg variants "$(shader_meta "$name" variants)" \
            '{name: $name, label: $label, variants: ($variants | split(" ") | map(select(. != "")))}'
    done < <(shader_names) | jq -sc --arg current "$(current)" '{current: $current, shaders: .}'
}

action=${1:-toggle}
case "$action" in
get)
    current
    ;;
list)
    entries
    ;;
status)
    status_json
    ;;
label)
    state=$(current)
    case "$state" in
    off) echo "○ Shader: Off" ;;
    custom) echo "● Shader: Custom" ;;
    *) echo "● Shader: $(label_of "$state")" ;;
    esac
    ;;
off)
    apply off
    ;;
reapply)
    read -r instance entry <<<"$(toggle_get_volatile shader)"
    # power saver clears the shader on purpose
    if [[ "$instance" == "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -n "${entry:-}" && "$(toggle_get_volatile powersaver)" != on ]] \
        && entry=$(entry_parse "$entry"); then
        load_entry "$entry"
    fi
    ;;
toggle)
    # on goes off, off brings back the last shader used
    if [[ "$(current)" != off ]]; then
        apply off
    else
        entry=$(entry_parse "$(toggle_get shader-last)" 2>/dev/null || entries | head -n 1)
        apply "$entry"
    fi
    ;;
set)
    entry=$(entry_parse "${2:?usage: $(basename "$0") set <shader>}")
    apply "$entry"
    ;;
*)
    # a bare entry name, so `get` output round-trips back through set
    if entry=$(entry_parse "$action" 2>/dev/null); then
        apply "$entry"
    else
        echo "usage: $(basename "$0") {get|list|status|label|toggle|off|reapply|set <shader>|<shader>}" >&2
        exit 1
    fi
    ;;
esac
