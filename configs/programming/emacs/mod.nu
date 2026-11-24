use module.nu *
use ../../core/wallust/scripts/editor.nu [editor-roles]
use ../../core/wallust/scripts/palette.nu [hex-to-rgb palette-rgb readable-on rgb-to-hex]
use ../../core/wallust/scripts/font.nu [font-load]

export const meta = {reads: [desktop/hyprland], packages: {pacman: [emacs]}}

const DOOM_URL = "https://github.com/doomemacs/doomemacs.git"
const DOOM_COMMIT = "7ccac7f643ad67baa25b216717cf8617a0903c69" # committed 2026-11-06
const DOOMDIR = [config/doom/init.el config/doom/config.el config/doom/packages.el]
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
    [$DOOM_COMMIT (open --raw config/doom/init.el) (open --raw config/doom/packages.el) $emacs] | str join "\n" | hash sha256
}

export def link [cfg: record] {
    let key = sync-key
    # the stamp doom sync was tracked by before it was recorded: one matching the key proves the sync already ran
    let synced = file-trim (emacs-dir | path join .local dot-synced)
    [
        (fetch-git $DOOM_URL $DOOM_COMMIT (emacs-dir))
        (files-into (xdg config doom) ...$DOOMDIR)
        (files-into (xdg config doom formatting) ...($FORMATTING | each { $"../formatting/config/($in)" }))
        (file-copy $"../formatting/scripts/($SORT_DERIVES)" (xdg config doom formatting $SORT_DERIVES) --mode 755)
        (step sync --key $key --done=($synced == $key) --requires (doom-bin) --network --timeout $SYNC_TIMEOUT)
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let font = font-load
    # the x11 build sizes frame text from xwayland's 96 dpi, and GDK_SCALE reaches only its gtk widgets; fold the
    # xwayland scale in so it matches the other x11 apps
    let size = ($font.size * (xwayland-scale-for $cfg) | math round)
    let reload = if (process-running emacs) { step theme-reload }
    let font_el = file-text (xdg cache $FONT) $"($LEXICAL)\n\(setq doom-font \(font-spec :family ($font.mono | to json) :size ($size).0\)\)\n" --generated
    let p = palette-load
    if $p == null { return [$font_el $reload] }
    let bg = $p.bg_conditioned | hex-to-rgb
    let accents = 1..6 | each {|i| [$"c($i)" ($p | get $"c($i)" | hex-to-rgb | readable-on $bg | rgb-to-hex --prefix "#")] }
        | into record
    let roles = palette-rgb emacs | editor-roles $bg | reject light | rename --block { $"r_($in)" }
    let shade = if $p.light == "1" { {mode: light, darken: lighten, lighten: darken} } else { {mode: dark, darken: darken, lighten: lighten} }
    [
        (file-render config/doom-pywal-theme.el.in (xdg cache $THEME) ($p | merge $accents | merge $roles | merge $shade | rename --block { str uppercase }) --generated)
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
