;;; doom-pywal-theme.el --- generated from the active wallust palette -*- lexical-binding: t; no-byte-compile: t; -*-
;;; Commentary:
;; rewritten by configs/wallust/scripts/generate-editor-themes.sh on every theme switch, do not edit
;;; Code:

(require 'doom-themes)

(def-doom-theme doom-pywal
  "A theme generated from the active wallust/pywal palette."
  :family 'doom-pywal
  :background-mode 'dark

  ((bg         '("#0F0F16"  "black"   "black"        ))
   (fg         '("#F290CE"  "#bfbfbf"       "brightwhite"  ))
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
   (red        '("#A16C97"  "#A16C97"  "red"           ))
   (orange     (doom-blend '("#A16C97" "#A16C97" "brightred") '("#6A7ABE" "#6A7ABE" "yellow") 0.5))
   (green      '("#8678B3"  "#8678B3"  "green"         ))
   (teal       (doom-blend '("#8678B3" "#8678B3" "brightgreen") '("#A96894" "#A96894" "cyan") 0.5))
   (yellow     '("#6A7ABE"  "#6A7ABE"  "yellow"        ))
   (blue       '("#AA6785"  "#AA6785"  "brightblue"    ))
   (dark-blue  (doom-darken '("#AA6785" "#AA6785" "blue") 0.4))
   (magenta    '("#9672AA"  "#9672AA"  "brightmagenta" ))
   (violet     (doom-blend '("#9672AA" "#9672AA" "magenta") '("#AA6785" "#AA6785" "blue") 0.5))
   (cyan       '("#A96894"  "#A96894"  "brightcyan"    ))
   (dark-cyan  (doom-darken '("#A96894" "#A96894" "cyan") 0.4))

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
