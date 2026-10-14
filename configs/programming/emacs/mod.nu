use module.nu *

export const meta = {packages: {pacman: [emacs hunspell-en_us]}}

const CONFIG_DIR = ".config/emacs"
const THEME = ".cache/wal/doom-pywal-theme.el"
const GRAMMAR_DIRS = [tree-sitter /usr/lib]
# the personal formatter configs lang.el passes where a project has none
const FORMATTING = [chktexrc clang-format latexindent.yaml prettierrc.json ruff.toml rustfmt.toml stylua.toml]

def config-dir []: nothing -> path { $nu.home-dir | path join $CONFIG_DIR }

def emacs-batch [...eval: string]: nothing -> list<string> {
    let dir = config-dir
    [emacs --batch --init-directory $dir -l ($dir | path join early-init.el) -l ($dir | path join init.el)] ++ ($eval | each {|e| [--eval $e] } | flatten)
}

# grammars my/treesit-install-langs builds that are neither built here nor shipped by pacman
def grammars-missing []: nothing -> list<string> {
    open --raw lang.el | parse --regex "(?s)defconst my/treesit-langs\\s+.\\((?<langs>[^)]*)\\)" | get 0.langs
    | split row --regex "\\s+" | where $it != ""
    | where {|lang| $GRAMMAR_DIRS | all {|d| not ((config-dir) | path join $d $"libtree-sitter-($lang).so" | path exists) } }
}

# the fallback editor has to work offline on its first start: packages and grammars install now, not on first launch.
# the stamp only after a full load, so an offline run tries again
export def link [cfg: record] {
    let dir = config-dir
    let stamp = $dir | path join elpa .dotfiles-prefetched
    let sources = glob *.el | append templates.eld | path basename
    [
        (files-into $dir ...$sources)
        ($FORMATTING | each {|f| file-copy ($"../formatting/($f)") ($dir | path join formatting $f) })
        (exec packages (emacs-batch $"\(write-region \"\" nil \"($stamp)\"\)") --creates $stamp)
        (if ($stamp | path exists) and (grammars-missing | is-not-empty) { [(exec grammars (emacs-batch "(my/treesit-install-langs)"))] } else { [] })
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-load
    if $p == null { return [] }
    let theme = $nu.home-dir | path join $THEME
    let shade = if $p.light == "1" { {mode: light, darken: lighten, lighten: darken} } else { {mode: dark, darken: darken, lighten: lighten} }
    [
        (file-render doom-pywal-theme.el.in $theme ($p | merge $shade | rename --block { str uppercase }) | file-text $theme $in.content --generated)
        (step theme-push)
    ]
}

# a running emacs reapplies through the entry point its own startup uses (ui.el)
export def theme-push []: nothing -> nothing {
    if (which emacsclient | is-empty) { return }
    # no server running is the common case
    try { ^timeout 5 emacsclient --eval "(my/apply-system-theme)" o+e>| ignore }
}
