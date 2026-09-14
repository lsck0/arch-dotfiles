#!/usr/bin/env bash
# Regenerates the Zed pywal theme and VSCodium's workbench.colorCustomizations
# from pywal's colors.json. Called from switch-wallpaper.sh's set_wallpaper(),
# same place every other themed app gets updated.
set -euo pipefail

# Install a generated file WITHOUT replacing the destination inode.
#
# `mv tmp dest` replaces the inode, which silently converts a symlink into a
# regular file. ~/.config/herdr/config.toml is a symlink into this repo
# (configs/herdr/link.sh), so a plain mv would break the link on the first
# wallpaper change and the repo copy would then quietly stop being what herdr
# actually reads. Resolving the destination first keeps the rename atomic
# while landing it on the symlink's target instead of on the symlink.
install_through_symlink() {
    local src=$1 dest=$2 real
    real=$(readlink -f "$dest" 2>/dev/null || echo "$dest")
    mv "$src" "$real"
}


COLORS_JSON="$HOME/.cache/wal/colors.json"
ZED_THEME="$HOME/projects/arch-dotfiles/configs/zed/themes/pywal.json"
VSCODE_SETTINGS="$HOME/.config/VSCodium/User/settings.json"

[[ -f "$COLORS_JSON" ]] || exit 0

bg=$(jq -r '.special.background' "$COLORS_JSON")
fg=$(jq -r '.special.foreground' "$COLORS_JSON")

# Floor bg's HSV value the same way configs/quickshell/Commons/Color.qml's
# toneMap(bg, 0.08, 0.26) does for the shell's own background. Without this,
# every consumer of $bg below (Zed, VSCodium, herdr) gets wallust's raw
# special.background verbatim — on this palette that's V≈0.039, so dark it
# renders as flat black. herdr's sidebar_bg was the one actually reported
# ("black bar on the left"), but panel_bg/editor backgrounds share the same
# raw value, so the floor applies before $bg branches to any of them rather
# than patching herdr's block alone.
bg=$(python3 -c "
import colorsys
hx = '$bg'.lstrip('#')
r, g, b = (int(hx[i:i+2], 16) / 255 for i in (0, 2, 4))
h, s, v = colorsys.rgb_to_hsv(r, g, b)
v = max(0.08, min(0.26, v))
r, g, b = colorsys.hsv_to_rgb(h, s, v)
print('#%02X%02X%02X' % (round(r * 255), round(g * 255), round(b * 255)))
")
c0=$(jq -r '.colors.color0' "$COLORS_JSON")
c1=$(jq -r '.colors.color1' "$COLORS_JSON")
c2=$(jq -r '.colors.color2' "$COLORS_JSON")
c3=$(jq -r '.colors.color3' "$COLORS_JSON")
c4=$(jq -r '.colors.color4' "$COLORS_JSON")
c5=$(jq -r '.colors.color5' "$COLORS_JSON")
c6=$(jq -r '.colors.color6' "$COLORS_JSON")
c7=$(jq -r '.colors.color7' "$COLORS_JSON")
c8=$(jq -r '.colors.color8' "$COLORS_JSON")
c9=$(jq -r '.colors.color9' "$COLORS_JSON")
c10=$(jq -r '.colors.color10' "$COLORS_JSON")
c11=$(jq -r '.colors.color11' "$COLORS_JSON")
c12=$(jq -r '.colors.color12' "$COLORS_JSON")
c13=$(jq -r '.colors.color13' "$COLORS_JSON")
c14=$(jq -r '.colors.color14' "$COLORS_JSON")
c15=$(jq -r '.colors.color15' "$COLORS_JSON")

# --- Zed theme extension ---
mkdir -p "$(dirname "$ZED_THEME")"
jq -n \
  --arg bg "$bg" --arg fg "$fg" \
  --arg c0 "$c0" --arg c1 "$c1" --arg c2 "$c2" --arg c3 "$c3" \
  --arg c4 "$c4" --arg c5 "$c5" --arg c6 "$c6" --arg c7 "$c7" \
  --arg c8 "$c8" --arg c9 "$c9" --arg c10 "$c10" --arg c11 "$c11" \
  --arg c12 "$c12" --arg c13 "$c13" --arg c14 "$c14" --arg c15 "$c15" \
  '{
    "$schema": "https://zed.dev/schema/themes/v0.2.0.json",
    name: "Pywal",
    author: "pywal (generated)",
    themes: [{
      name: "Pywal",
      appearance: "dark",
      style: {
        background: $bg,
        "editor.background": $bg,
        "editor.foreground": $fg,
        "editor.gutter.background": $bg,
        "editor.active_line.background": $c8,
        "editor.line_number": $c8,
        "editor.active_line_number": $fg,
        text: $fg,
        "text.muted": $c8,
        "text.accent": $c4,
        border: $c8,
        "border.variant": $c0,
        "element.background": $c0,
        "element.hover": $c8,
        "element.selected": $c4,
        "surface.background": $bg,
        "panel.background": $bg,
        "tab.active_background": $bg,
        "tab.inactive_background": $c0,
        "tab_bar.background": $c0,
        "status_bar.background": $c0,
        "title_bar.background": $c0,
        "toolbar.background": $bg,
        "terminal.background": $bg,
        "terminal.foreground": $fg,
        "terminal.ansi.black": $c0,
        "terminal.ansi.red": $c1,
        "terminal.ansi.green": $c2,
        "terminal.ansi.yellow": $c3,
        "terminal.ansi.blue": $c4,
        "terminal.ansi.magenta": $c5,
        "terminal.ansi.cyan": $c6,
        "terminal.ansi.white": $c7,
        "terminal.ansi.bright_black": $c8,
        "terminal.ansi.bright_red": $c9,
        "terminal.ansi.bright_green": $c10,
        "terminal.ansi.bright_yellow": $c11,
        "terminal.ansi.bright_blue": $c12,
        "terminal.ansi.bright_magenta": $c13,
        "terminal.ansi.bright_cyan": $c14,
        "terminal.ansi.bright_white": $c15,
        "syntax": {
          "comment": { color: $c8 },
          "string": { color: $c2 },
          "keyword": { color: $c4 },
          "function": { color: $c3 },
          "type": { color: $c6 },
          "variable": { color: $fg },
          "constant": { color: $c5 },
          "number": { color: $c5 }
        }
      }
    }]
  }' > "$ZED_THEME"

# --- VSCodium workbench.colorCustomizations ---
if [[ -d "$(dirname "$VSCODE_SETTINGS")" ]] || mkdir -p "$(dirname "$VSCODE_SETTINGS")" 2>/dev/null; then
  [[ -f "$VSCODE_SETTINGS" ]] || echo '{}' > "$VSCODE_SETTINGS"
  tmp=$(mktemp)
  jq --arg bg "$bg" --arg fg "$fg" --arg c0 "$c0" --arg c4 "$c4" --arg c8 "$c8" \
    '."workbench.colorCustomizations" = {
      "editor.background": $bg,
      "editor.foreground": $fg,
      "sideBar.background": $c0,
      "activityBar.background": $c0,
      "statusBar.background": $c0,
      "titleBar.activeBackground": $c0,
      "tab.activeBackground": $bg,
      "tab.inactiveBackground": $c0,
      "focusBorder": $c4,
      "terminal.background": $bg,
      "terminal.foreground": $fg
    }' "$VSCODE_SETTINGS" > "$tmp" && mv "$tmp" "$VSCODE_SETTINGS"
fi

# --- herdr [theme.custom] (marker-delimited surgical replace — config.toml is
# hand-written/tracked, so this must never touch anything outside the markers) ---
HERDR_CONFIG="$HOME/.config/herdr/config.toml"

# herdr's own background. Issue 21 v3: v1 used the ghostty-composited colour
# (too light, mismatched the opaque pane). v2 hardcoded a hand-picked value
# darker than even $bg's own HSV floor (#07090c vs. a floored $bg around
# #0B0E14) — reported back as "TOOOOO DARK", because on this palette the raw
# background's V is ~0.078, already right at $bg's 0.08 floor, so v2's extra
# darkening was pure regression with no floor left under it. Fix: give herdr
# specifically a *second, higher* floor (0.16, distinctly lighter than $bg's
# shared 0.08) rather than reusing $bg verbatim — Zed/VSCodium keep the
# original $bg floor unchanged since neither got this complaint.
herdr_bg=$(python3 -c "
import colorsys
hx = '$bg'.lstrip('#')
r, g, b = (int(hx[i:i+2], 16) / 255 for i in (0, 2, 4))
h, s, v = colorsys.rgb_to_hsv(r, g, b)
v = max(0.16, v)
r, g, b = colorsys.hsv_to_rgb(h, s, v)
print('#%02X%02X%02X' % (round(r * 255), round(g * 255), round(b * 255)))
")
if [[ -f "$HERDR_CONFIG" ]] && grep -q "# BEGIN PYWAL THEME" "$HERDR_CONFIG"; then
  # Only sidebar_bg/panel_bg/active_row_bg/selection_bg/accent/red/green used
  # to be set here. herdr's [theme.custom] schema (config-reference.json)
  # also has surface0/surface1/surface_dim/overlay0/overlay1/text/subtext0
  # and mauve/yellow/blue/teal/peach — Catppuccin's own token names, which
  # this is a reskin of. Leaving them unset doesn't mean "invisible", it
  # means herdr falls back to its stock (non-wallust) theme for whatever
  # uses them — which on this machine was a neutral grey, sitting right next
  # to the navy-tinted bg/accent tokens that WERE set. Reported as "a
  # transparency difference between the main window and the sidebar"; it
  # was actually two different color families in the same window, not
  # alpha (config-reference.json's own token comment documents
  # `panel_bg = "reset"` as a real, supported value — a pass-through to the
  # host terminal's own background/opacity, not a solid color. Corrects the
  # earlier "no opacity/transparency keys at all" note here — that read the
  # override syntax as if hex/named/rgb() were the ONLY accepted forms).
  # sidebar_bg/panel_bg are now set to "reset" (real sidebar/topbar
  # transparency, following ghostty's background-opacity through) instead
  # of a solid pre-blended hex — active_row_bg/selection_bg/surface*/
  # overlay*/subtext0 stay solid since those need to sit legibly on TOP of
  # whatever shows through, so pre-blending foreground into background at
  # increasing opacity (mirroring configs/quickshell/Commons/Color.qml's
  # selectedBackground convention) is still correct for them specifically.
  # Same ramp order as Catppuccin: surface_dim ~= bg, then
  # surface0 < surface1 < overlay0 < overlay1 < subtext0 < text(=fg).
  read -r active_row_bg selection_bg surface_dim surface0 surface1 overlay0 overlay1 subtext0 < <(python3 -c "
fg = '$fg'.lstrip('#')
bg = '$herdr_bg'.lstrip('#')
fr, fgc, fb = (int(fg[i:i+2], 16) for i in (0, 2, 4))
br, bgc, bb = (int(bg[i:i+2], 16) for i in (0, 2, 4))
def blend(t):
    return '#%02x%02x%02x' % (
        round(fr * t + br * (1 - t)),
        round(fgc * t + bgc * (1 - t)),
        round(fb * t + bb * (1 - t)),
    )
# Issue 21 v3: v2 pulled the whole ramp too close to bg on top of an
# already-too-dark bg, compounding into TOOOOO DARK. With herdr_bg now
# floored lighter (see above), restore fractions closer to the original
# Catppuccin-style ramp so active/selection/surface states stay legible.
print(blend(0.06), blend(0.11), blend(0.0), blend(0.08), blend(0.14), blend(0.22), blend(0.34), blend(0.65))
")

  tmp=$(mktemp)
  awk -v bg="$herdr_bg" -v fg="$fg" -v accent="$c4" -v red="$c1" -v green="$c2" \
      -v yellow="$c3" -v blue="$c4" -v mauve="$c5" -v teal="$c6" -v peach="$c11" \
      -v active="$active_row_bg" -v sel="$selection_bg" \
      -v surface_dim="$surface_dim" -v surface0="$surface0" -v surface1="$surface1" \
      -v overlay0="$overlay0" -v overlay1="$overlay1" -v subtext0="$subtext0" '
    /# BEGIN PYWAL THEME/ {
      print
      print "[theme.custom]"
      print "sidebar_bg = \"reset\""
      print "panel_bg = \"reset\""
      print "active_row_bg = \"" active "\""
      print "selection_bg = \"" sel "\""
      print "accent = \"" accent "\""
      print "red = \"" red "\""
      print "green = \"" green "\""
      print "surface_dim = \"" surface_dim "\""
      print "surface0 = \"" surface0 "\""
      print "surface1 = \"" surface1 "\""
      print "overlay0 = \"" overlay0 "\""
      print "overlay1 = \"" overlay1 "\""
      print "text = \"" fg "\""
      print "subtext0 = \"" subtext0 "\""
      print "yellow = \"" yellow "\""
      print "blue = \"" blue "\""
      print "mauve = \"" mauve "\""
      print "teal = \"" teal "\""
      print "peach = \"" peach "\""
      skip = 1
      next
    }
    /# END PYWAL THEME/ { skip = 0 }
    skip { next }
    { print }
  ' "$HERDR_CONFIG" > "$tmp" && install_through_symlink "$tmp" "$HERDR_CONFIG"

  herdr server reload-config >/dev/null 2>&1 || true
fi
