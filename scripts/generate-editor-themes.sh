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

# herdr's own background, which is NOT the same as $bg used for Zed/VSCodium.
#
# herdr runs inside ghostty, and ghostty is semi-transparent
# (background-opacity in configs/ghostty/config). Terminal transparency only
# applies to cells with no explicit background colour, so the shell pane shows
# blurred wallpaper through it while herdr's sidebar — which herdr paints with
# a solid colour — stays opaque. The sidebar therefore reads as a dark slab
# next to a visibly lighter pane. Reported twice now; herdr has no opacity
# keys at all (config-reference.json), so it cannot be made transparent to
# match.
#
# What it CAN do is match the pane's *apparent* colour: ghostty's background
# composited over the wallpaper at ghostty's own opacity. Both inputs are read
# rather than assumed, so this tracks a wallpaper change and an opacity change
# on its own instead of drifting the moment either moves.
#
# The [0.08, 0.26] floor still applies underneath: a near-black wallpaper must
# not bring back the original "black bar on the left" report.
GHOSTTY_CONFIG="$HOME/projects/arch-dotfiles/configs/ghostty/config"
WALLPAPER="$HOME/.cache/wal/wallpaper"
herdr_bg=$(python3 -c "
import colorsys, re, subprocess, sys

floored = '$bg'

def read_opacity(path):
    try:
        for line in open(path):
            m = re.match(r'\s*background-opacity\s*=\s*([0-9.]+)', line)
            if m:
                return max(0.0, min(1.0, float(m.group(1))))
    except OSError:
        pass
    return 1.0

opacity = read_opacity('$GHOSTTY_CONFIG')
term_bg = '$(sed -n "s/^background = //p" "$HOME/.cache/wal/ghostty.conf" 2>/dev/null | head -1)'.lstrip('#')
if len(term_bg) != 6 or opacity >= 0.999:
    print(floored); sys.exit()

try:
    mean = subprocess.run(
        ['magick', '$WALLPAPER', '-resize', '1x1!', '-format',
         '%[fx:int(255*r)],%[fx:int(255*g)],%[fx:int(255*b)]', 'info:'],
        capture_output=True, text=True, timeout=10, check=True).stdout.strip()
    mr, mg, mb = (int(x) for x in mean.split(','))
except Exception:
    print(floored); sys.exit()

tr, tg, tb = (int(term_bg[i:i+2], 16) for i in (0, 2, 4))
comp = [tr * opacity + mr * (1 - opacity),
        tg * opacity + mg * (1 - opacity),
        tb * opacity + mb * (1 - opacity)]

# Same value floor/ceiling the rest of this script applies to \$bg.
h, sat, v = colorsys.rgb_to_hsv(*[c / 255 for c in comp])
r, g, b = colorsys.hsv_to_rgb(h, sat, max(0.08, min(0.26, v)))
print('#%02X%02X%02X' % (round(r * 255), round(g * 255), round(b * 255)))
")
[[ -n "$herdr_bg" ]] || herdr_bg="$bg"
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
  # alpha (herdr has no opacity/transparency keys at all, confirmed against
  # config-reference.json — every "surface" here is an opaque solid color).
  # active_row_bg/selection_bg/surface*/overlay*/subtext0: foreground
  # blended into background at increasing opacity, mirroring
  # configs/quickshell/Commons/Color.qml's selectedBackground convention
  # (herdr's theme.custom has no alpha channel, so pre-blend to a solid hex
  # instead). Same ramp order as Catppuccin: surface_dim ~= bg, then
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
print(blend(0.06), blend(0.12), blend(0.0), blend(0.08), blend(0.14), blend(0.24), blend(0.34), blend(0.65))
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
      print "sidebar_bg = \"" bg "\""
      print "panel_bg = \"" bg "\""
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
