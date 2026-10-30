use module.nu *
use ../../core/wallust/palette.nu [OPACITY_SURFACE hex-to-rgb readable-on rgb-to-hex]
use ../../core/wallust/font.nu [font-load]

export const meta = {packages: {pacman: [emacs hunspell-en_us]}}

const CONFIG_DIR = ".config/emacs"
const THEME = "wal/doom-pywal-theme.el"
const FRAME = "wal/emacs-frame.el"
const FONT = "wal/emacs-font.el"
const GRAMMAR_DIRS = [tree-sitter /usr/lib]
const LEXICAL = ";;; -*- lexical-binding: t; -*-"
const FORMATTING = [clang-format prettierrc.json ruff.toml rustfmt.toml stylua.toml]
const UPGRADE = "(progn (require 'package)
  (setq package-archives '((\"gnu\" . \"https://elpa.gnu.org/packages/\")
                            (\"nongnu\" . \"https://elpa.nongnu.org/nongnu/\")
                            (\"melpa\" . \"https://melpa.org/packages/\")))
  (package-initialize)
  (package-refresh-contents)
  (package-upgrade-all))"

def config-dir []: nothing -> path { $nu.home-dir | path join $CONFIG_DIR }

def emacs-batch [...eval: string]: nothing -> list<string> {
    let dir = config-dir
    # debug-on-error makes use-package rethrow a failed install instead of only warning, so the batch exits non-zero
    ([emacs --batch --init-directory $dir --eval "(setq debug-on-error t)" -l ($dir | path join early-init.el)
        -l ($dir | path join init.el)] ++ ($eval | each {|e| [--eval $e] } | flatten))
}

# use-package names that always-ensure installs (all but `:ensure nil`) with no dir in elpa/ yet
def packages-missing []: nothing -> list<string> {
    let installed = ls --short-names (config-dir | path join elpa) | get name
        | each { str replace --regex '-[0-9][0-9.]*$' '' }
    glob *.el | each { open --raw $in | split row "(use-package " | skip 1 }
    | flatten
    | where {|form| not ($form | str contains ":ensure nil") }
    | each { split row --regex '[\s)]' | first }
    | where $it not-in $installed
}

def elpa-ready []: nothing -> bool { (config-dir | path join elpa | path exists) and (packages-missing | is-empty) }

def grammars-missing []: nothing -> list<string> {
    open --raw lang.el | parse --regex "(?s)defconst my/treesit-langs\\s+.\\((?<langs>[^)]*)\\)" | get 0.langs
    | split row --regex "\\s+" | where $it != ""
    | where {|lang| $GRAMMAR_DIRS | all {|d| not ((config-dir) | path join $d $"libtree-sitter-($lang).so" | path exists) } }
}

export def link [cfg: record] {
    let dir = config-dir
    let sources = glob *.el | append templates.eld | path basename
    [
        (files-into $dir ...$sources)
        ($FORMATTING | each {|f| file-copy ($"../formatting/($f)") ($dir | path join formatting $f) })
        (file-copy ../formatting/sort-derives-stdout.nu ($dir | path join formatting sort-derives-stdout.nu) --mode 755)
        (if not (elpa-ready) or (grammars-missing | is-not-empty) { [(step prefetch)] } else { [] })
    ]
}

# Install the packages, then the grammars in the same run: their installer lives in a package, so a fresh install
# has to load the packages first.
export def prefetch []: nothing -> nothing {
    if not (elpa-ready) { run-external ...(emacs-batch) }
    if (grammars-missing | is-not-empty) { run-external ...(emacs-batch "(my/treesit-install-langs)") }
}

export def theme [cfg: record, wallpaper: string] {
    let font = font-load
    # emacs renders at the raw point size and, unlike the gtk apps, gets no desktop scale; fold it in so it matches
    let size = ($font.size * $font.scale | math round)
    let font_el = file-text (xdg cache $FONT) $"($LEXICAL)\n\(setq my/font-family ($font.mono | to json) my/font-size ($size)\)\n" --generated
    let p = palette-load
    if $p == null { return [$font_el] }
    let theme = xdg cache $THEME
    let bg = $p.bg_conditioned | hex-to-rgb
    let accents = 1..6 | each {|i| [$"c($i)" ($p | get $"c($i)" | hex-to-rgb | readable-on $bg | rgb-to-hex --prefix "#")] }
        | into record
    let shade = if $p.light == "1" { {mode: light, darken: lighten, lighten: darken} } else { {mode: dark, darken: darken, lighten: lighten} }
    let strings = [[background-color $p.bg_conditioned] [foreground-color $p.fg]]
        | each { $"\(push '\(($in.0) . \"($in.1)\"\) default-frame-alist\)" }
    let alpha = $"\(push '\(alpha-background . ($OPACITY_SURFACE * 100 | math round)\) default-frame-alist\)"
    let frame = ($strings ++ [$alpha]) | str join "\n"
    [
        (file-render doom-pywal-theme.el.in $theme ($p | merge $accents | merge $shade | rename --block { str uppercase }) --generated)
        (file-text (xdg cache $FRAME) $"($LEXICAL)\n($frame)\n" --generated)
        $font_el
        (step theme-push)
    ]
}

export def theme-push []: nothing -> nothing {
    if (which emacsclient | is-empty) { return }
    let font = font-load
    let size = ($font.size * $font.scale | math round)
    # default-frame-alist's font wins over the faces on every frame made later
    let faces = "(dolist (face '(default fixed-pitch variable-pitch)) (set-face-attribute face nil :family my/font-family :height (* 10 my/font-size))) (setf (alist-get 'font default-frame-alist) (format \"%s-%d\" my/font-family my/font-size))"
    let eval = $"\(progn \(setq my/font-family ($font.mono | to json) my/font-size ($size)\) ($faces) \(my/apply-system-theme\)\)"
    try { ^timeout 5 emacsclient --eval $eval o+e>| ignore }
}

export def update [cfg: record]: nothing -> nothing {
    ^emacs --batch --init-directory (config-dir) --eval $UPGRADE
}
