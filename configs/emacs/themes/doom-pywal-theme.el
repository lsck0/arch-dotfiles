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

  ((bg         '("#1E2127"  "black"   "black"        ))
   (fg         '("#ABB2BF"  "#bfbfbf"       "brightwhite"  ))
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
   (red        '("#E06C75"  "#E06C75"  "red"           ))
   (orange     (doom-blend '("#E06C75" "#E06C75" "brightred") '("#D19A66" "#D19A66" "yellow") 0.5))
   (green      '("#98C379"  "#98C379"  "green"         ))
   (teal       (doom-blend '("#98C379" "#98C379" "brightgreen") '("#56B6C2" "#56B6C2" "cyan") 0.5))
   (yellow     '("#D19A66"  "#D19A66"  "yellow"        ))
   (blue       '("#61AFEF"  "#61AFEF"  "brightblue"    ))
   (dark-blue  (doom-darken '("#61AFEF" "#61AFEF" "blue") 0.4))
   (magenta    '("#C678DD"  "#C678DD"  "brightmagenta" ))
   (violet     (doom-blend '("#C678DD" "#C678DD" "magenta") '("#61AFEF" "#61AFEF" "blue") 0.5))
   (cyan       '("#56B6C2"  "#56B6C2"  "brightcyan"    ))
   (dark-cyan  (doom-darken '("#56B6C2" "#56B6C2" "cyan") 0.4))

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
