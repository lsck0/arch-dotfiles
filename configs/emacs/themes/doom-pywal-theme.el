;;; doom-pywal-theme.el --- generated from the active wallust palette -*- lexical-binding: t; no-byte-compile: t; -*-
;;; Commentary:
;; rewritten by configs/wallust/scripts/generate-editor-themes.sh on every theme switch, do not edit
;;; Code:

(require 'doom-themes)

(def-doom-theme doom-pywal
  "A theme generated from the active wallust/pywal palette."
  :family 'doom-pywal
  :background-mode 'dark

  ((bg         '("#1A1B26"  "black"   "black"        ))
   (fg         '("#C0CAF5"  "#bfbfbf"       "brightwhite"  ))
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
   (red        '("#F7768E"  "#F7768E"  "red"           ))
   (orange     (doom-blend '("#F7768E" "#F7768E" "brightred") '("#E0AF68" "#E0AF68" "yellow") 0.5))
   (green      '("#9ECE6A"  "#9ECE6A"  "green"         ))
   (teal       (doom-blend '("#9ECE6A" "#9ECE6A" "brightgreen") '("#7DCFFF" "#7DCFFF" "cyan") 0.5))
   (yellow     '("#E0AF68"  "#E0AF68"  "yellow"        ))
   (blue       '("#7AA2F7"  "#7AA2F7"  "brightblue"    ))
   (dark-blue  (doom-darken '("#7AA2F7" "#7AA2F7" "blue") 0.4))
   (magenta    '("#BB9AF7"  "#BB9AF7"  "brightmagenta" ))
   (violet     (doom-blend '("#BB9AF7" "#BB9AF7" "magenta") '("#7AA2F7" "#7AA2F7" "blue") 0.5))
   (cyan       '("#7DCFFF"  "#7DCFFF"  "brightcyan"    ))
   (dark-cyan  (doom-darken '("#7DCFFF" "#7DCFFF" "cyan") 0.4))

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
