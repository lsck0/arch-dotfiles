#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# zed, vscodium, herdr and emacs themes from pywal colors.json
set -euo pipefail

# replace the symlink target, not the link
install_through_symlink() {
    local src=$1 dest=$2 real
    real=$(readlink -f "$dest" 2>/dev/null || echo "$dest")
    mv "$src" "$real"
}

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
COLORS_JSON="$HOME/.cache/wal/colors.json"
ZED_THEME="$DOTFILES/configs/programming/zed/themes/pywal.json"
VSCODE_SETTINGS="$HOME/.config/VSCodium/User/settings.json"
EMACS_THEME_DIR="$DOTFILES/configs/programming/emacs/themes"
EMACS_THEME="$EMACS_THEME_DIR/doom-pywal-theme.el"

[[ -f "$COLORS_JSON" ]] || exit 0

bg=$(jq -r '.special.background' "$COLORS_JSON")
fg=$(jq -r '.special.foreground' "$COLORS_JSON")

# light detection uses the raw bg, before tone_map floors it dark; herdr wants a lighter floor still
read -r bg_is_light toned_bg herdr_bg < <(python3 - "$bg" "$SCRIPT_DIR/lib" <<'PY'
import sys
sys.path.insert(0, sys.argv[2])
from palette import hex_to_rgb, rgb_to_hex, tone_map
raw = hex_to_rgb(sys.argv[1])
toned = rgb_to_hex(tone_map(raw), "#")
herdr = rgb_to_hex(tone_map(hex_to_rgb(toned), 0.16, 1.0), "#")
print(int(0.2126 * raw[0] + 0.7152 * raw[1] + 0.0722 * raw[2] > 0.5), toned, herdr)
PY
)

if [[ "$bg_is_light" == 1 ]]; then
    EMACS_MODE=light
    EMACS_BG=$bg
    EMACS_DARKEN=lighten
    EMACS_LIGHTEN=darken
else
    EMACS_MODE=dark
    EMACS_BG=$toned_bg
    EMACS_DARKEN=darken
    EMACS_LIGHTEN=lighten
fi
bg=$toned_bg

read -r c0 c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 c11 c12 c13 c14 c15 < <(
    jq -r '[range(16) as $i | .colors["color\($i)"]] | @tsv' "$COLORS_JSON"
)

# zed
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

# vscodium
if [[ -d "$(dirname "$VSCODE_SETTINGS")" ]] || mkdir -p "$(dirname "$VSCODE_SETTINGS")" 2>/dev/null; then
  [[ -f "$VSCODE_SETTINGS" ]] || echo '{}' > "$VSCODE_SETTINGS"
  tmp=$(mktemp)
  jq --arg bg "$bg" --arg fg "$fg" --arg c0 "$c0" --arg c4 "$c4" --arg c8 "$c8" \
    '."workbench.colorCustomizations" += {
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
    }' "$VSCODE_SETTINGS" > "$tmp" && install_through_symlink "$tmp" "$VSCODE_SETTINGS"
fi

# herdr: only rewrite between the pywal markers
HERDR_CONFIG="$HOME/.config/herdr/config.toml"

if [[ -f "$HERDR_CONFIG" ]] && grep -q "# BEGIN PYWAL THEME" "$HERDR_CONFIG"; then
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

# emacs doom theme
mkdir -p "$EMACS_THEME_DIR"
cat > "$EMACS_THEME" <<EOF
;;; doom-pywal-theme.el --- generated from the active wallust palette -*- lexical-binding: t; no-byte-compile: t; -*-
;;; Commentary:
;; rewritten by configs/base/wallust/scripts/generate-editor-themes.sh on every theme switch, do not edit
;;; Code:

(require 'doom-themes)

(def-doom-theme doom-pywal
  "A theme generated from the active wallust/pywal palette."
  :family 'doom-pywal
  :background-mode '$EMACS_MODE

  ((bg         '("$EMACS_BG"  "black"   "black"        ))
   (fg         '("$fg"  "#bfbfbf"       "brightwhite"  ))
   (bg-alt     (doom-$EMACS_DARKEN bg 0.10))
   (fg-alt     (doom-$EMACS_LIGHTEN fg 0.20))

   (base0      (doom-$EMACS_DARKEN bg 0.20))
   (base1      (doom-$EMACS_DARKEN bg 0.10))
   (base2      bg)
   (base3      (doom-$EMACS_LIGHTEN bg 0.10))
   (base4      (doom-blend bg fg 0.25))
   (base5      (doom-blend bg fg 0.45))
   (base6      (doom-blend bg fg 0.60))
   (base7      (doom-blend bg fg 0.75))
   (base8      (doom-$EMACS_LIGHTEN fg 0.20))

   (grey       base4)
   (red        '("$c1"  "$c1"  "red"           ))
   (orange     (doom-blend '("$c1" "$c1" "brightred") '("$c3" "$c3" "yellow") 0.5))
   (green      '("$c2"  "$c2"  "green"         ))
   (teal       (doom-blend '("$c2" "$c2" "brightgreen") '("$c6" "$c6" "cyan") 0.5))
   (yellow     '("$c3"  "$c3"  "yellow"        ))
   (blue       '("$c4"  "$c4"  "brightblue"    ))
   (dark-blue  (doom-darken '("$c4" "$c4" "blue") 0.4))
   (magenta    '("$c5"  "$c5"  "brightmagenta" ))
   (violet     (doom-blend '("$c5" "$c5" "magenta") '("$c4" "$c4" "blue") 0.5))
   (cyan       '("$c6"  "$c6"  "brightcyan"    ))
   (dark-cyan  (doom-darken '("$c6" "$c6" "cyan") 0.4))

   ;; mandatory "universal syntax classes": doom-themes-base errors without them
   (highlight      blue)
   (vertical-bar   (doom-$EMACS_DARKEN bg 0.15))
   (selection      dark-blue)
   (builtin        magenta)
   (comments       base5)
   (doc-comments   (doom-lighten base5 0.25))
   (constants      violet)
   (functions      yellow)
   (keywords       blue)
   (methods        cyan)
   (operators      blue)
   (type           cyan)
   (strings        green)
   (variables      fg)
   (numbers        magenta)
   (region         (doom-blend bg fg 0.20))
   (error          red)
   (warning        yellow)
   (success        green)
   (vc-modified    orange)
   (vc-added       green)
   (vc-deleted     red)))

(provide-theme 'doom-pywal)
;;; doom-pywal-theme.el ends here
EOF
