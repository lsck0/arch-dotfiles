use module.nu *
use ../../core/wallust/palette.nu [hex-to-rgb readable-on rgb-to-hex]
use ../../core/wallust/font.nu [font-load]

export const meta = {packages: {pacman: [emacs]}}

const DOOM_URL = "https://github.com/doomemacs/doomemacs.git"
const DOOM_COMMIT = "59cdaa32ae933469bb6a1fb3cadee8a988c15968"
const DOOMDIR = [doom/init.el doom/config.el doom/packages.el]
const FORMATTING = [clang-format prettierrc.json ruff.toml rustfmt.toml stylua.toml]
const SORT_DERIVES = "sort-derives-stdout.nu"
const THEME = "wal/doom-pywal-theme.el"
const FONT = "wal/emacs-font.el"
const LEXICAL = ";;; -*- lexical-binding: t; -*-"
const RELOAD_TIMEOUT_S = "5"
# a fresh sync clones and native-compiles every package: past converge's 20min
const SYNC_TIMEOUT = 60min

def emacs-dir []: nothing -> path { xdg config emacs }

def doom-bin []: nothing -> path { emacs-dir | path join bin doom }

# What doom sync installs from: the pin, the module and package lists, and the Emacs that compiles them.
def sync-key []: nothing -> string {
    let emacs = ^pacman -Q emacs | complete | get stdout | str trim
    [$DOOM_COMMIT (open --raw doom/init.el) (open --raw doom/packages.el) $emacs] | str join "\n" | hash sha256
}

export def link [cfg: record] {
    let key = sync-key
    # the stamp doom sync was tracked by before it was recorded: one matching the key proves the sync already ran
    let synced = try { open --raw (emacs-dir | path join .local dot-synced) | str trim } catch { "" }
    [
        (fetch-git $DOOM_URL $DOOM_COMMIT (emacs-dir))
        (files-into (xdg config doom) ...$DOOMDIR)
        (files-into (xdg config doom formatting) ...($FORMATTING | each { $"../formatting/($in)" }))
        (file-copy $"../formatting/($SORT_DERIVES)" (xdg config doom formatting $SORT_DERIVES) --mode 755)
        (step sync --key $key --done=($synced == $key) --requires (doom-bin) --network --timeout $SYNC_TIMEOUT)
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let font = font-load
    # emacs renders at the raw point size and, unlike the gtk apps, gets no desktop scale; fold it in so it matches
    let size = ($font.size * $font.scale | math round)
    let reload = if (process-running emacs) { [(step theme-reload)] } else { [] }
    let font_el = file-text (xdg cache $FONT) $"($LEXICAL)\n\(setq doom-font \(font-spec :family ($font.mono | to json) :size ($size).0\)\)\n" --generated
    let p = palette-load
    if $p == null { return [$font_el $reload] }
    let bg = $p.bg_conditioned | hex-to-rgb
    let accents = 1..6 | each {|i| [$"c($i)" ($p | get $"c($i)" | hex-to-rgb | readable-on $bg | rgb-to-hex --prefix "#")] }
        | into record
    let shade = if $p.light == "1" { {mode: light, darken: lighten, lighten: darken} } else { {mode: dark, darken: darken, lighten: lighten} }
    [
        (file-render doom-pywal-theme.el.in (xdg cache $THEME) ($p | merge $accents | merge $shade | rename --block { str uppercase }) --generated)
        $font_el
        $reload
    ]
}

# Recolours a running emacs; -a false keeps emacsclient from starting a daemon, and one without a server is skipped.
export def theme-reload []: nothing -> nothing {
    try { ^timeout $RELOAD_TIMEOUT_S emacsclient -a false --eval "(my/theme-reload)" o+e>| ignore }
}

# Installs the packages doom pins for this commit and the enabled modules; --force answers its prompts.
export def sync []: nothing -> nothing {
    run-external (doom-bin) "--force" sync
}
