;;; doom-pywal-theme.el --- generated from the active wallust palette -*- lexical-binding: t; no-byte-compile: t; -*-
;;; Commentary:
;; rewritten by configs/wallust/scripts/generate-editor-themes.sh on every theme switch, do not edit
;;; Code:

(require 'doom-themes)

(def-doom-theme doom-pywal
  "A theme generated from the active wallust/pywal palette."
  :family 'doom-pywal
  :background-mode 'dark

  ((bg         '("#0A1114"  "black"   "black"        ))
   (fg         '("#C7C2D8"  "#bfbfbf"       "brightwhite"  ))
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
   (red        '("#847E89"  "#847E89"  "red"           ))
   (orange     (doom-blend '("#847E89" "#847E89" "brightred") '("#9E7782" "#9E7782" "yellow") 0.5))
   (green      '("#5F8496"  "#5F8496"  "green"         ))
   (teal       (doom-blend '("#5F8496" "#5F8496" "brightgreen") '("#827E92" "#827E92" "cyan") 0.5))
   (yellow     '("#9E7782"  "#9E7782"  "yellow"        ))
   (blue       '("#8F7882"  "#8F7882"  "brightblue"    ))
   (dark-blue  (doom-darken '("#8F7882" "#8F7882" "blue") 0.4))
   (magenta    '("#6D84A3"  "#6D84A3"  "brightmagenta" ))
   (violet     (doom-blend '("#6D84A3" "#6D84A3" "magenta") '("#8F7882" "#8F7882" "blue") 0.5))
   (cyan       '("#827E92"  "#827E92"  "brightcyan"    ))
   (dark-cyan  (doom-darken '("#827E92" "#827E92" "cyan") 0.4))

   ;; mandatory "universal syntax classes": doom-themes-base errors without them
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
