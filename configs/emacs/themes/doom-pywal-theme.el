;;; doom-pywal-theme.el --- generated from the active wallust palette -*- lexical-binding: t; no-byte-compile: t; -*-
;;; Commentary:
;; GENERATED FILE — do not edit. Rewritten by
;; configs/wallust/scripts/generate-editor-themes.sh on every theme switch.
;;; Code:

(require 'doom-themes)

(def-doom-theme doom-pywal
  "A theme generated from the active wallust/pywal palette."
  :family 'doom-pywal
  :background-mode 'dark

  ((bg         '("#0B0E14"  "black"   "black"        ))
   (fg         '("#BFBDB6"  "#bfbfbf"       "brightwhite"  ))
   (bg-alt     (doom-darken bg 0.10))
   (fg-alt     (doom-lighten fg 0.20))

   (base0      (doom-darken bg 0.20))
   (base1      (doom-darken bg 0.10))
   (base2      bg)
   (base3      (doom-lighten bg 0.10))
   (base4      (doom-blend bg fg 0.25))
   (base5      (doom-blend bg fg 0.45))
   (base6      (doom-blend bg fg 0.60))
   (base7      (doom-blend bg fg 0.75))
   (base8      (doom-lighten fg 0.20))

   (grey       base4)
   (red        '("#F07178"  "#F07178"  "red"           ))
   (orange     (doom-blend '("#F07178" "#F07178" "brightred") '("#E6B450" "#E6B450" "yellow") 0.5))
   (green      '("#AAD94C"  "#AAD94C"  "green"         ))
   (teal       (doom-blend '("#AAD94C" "#AAD94C" "brightgreen") '("#95E6CB" "#95E6CB" "cyan") 0.5))
   (yellow     '("#E6B450"  "#E6B450"  "yellow"        ))
   (blue       '("#39BAE6"  "#39BAE6"  "brightblue"    ))
   (dark-blue  (doom-darken '("#39BAE6" "#39BAE6" "blue") 0.4))
   (magenta    '("#D2A6FF"  "#D2A6FF"  "brightmagenta" ))
   (violet     (doom-blend '("#D2A6FF" "#D2A6FF" "magenta") '("#39BAE6" "#39BAE6" "blue") 0.5))
   (cyan       '("#95E6CB"  "#95E6CB"  "brightcyan"    ))
   (dark-cyan  (doom-darken '("#95E6CB" "#95E6CB" "cyan") 0.4))

   ;; mandatory "universal syntax classes" — doom-themes-base errors without them
   (highlight      blue)
   (vertical-bar   (doom-darken bg 0.15))
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
