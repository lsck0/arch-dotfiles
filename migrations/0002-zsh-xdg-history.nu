# zsh's history moves to the state dir and its completion dump to the cache, out of $HOME (core/zsh zshrc)

def old-history []: nothing -> path { $nu.home-dir | path join .zsh_history }

def new-history []: nothing -> path {
    $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state) | path join zsh history
}

def dumps []: nothing -> list<path> { glob ($nu.home-dir | path join ".zcompdump*") }

export def up []: nothing -> nothing {
    let old = old-history
    let new = new-history
    if ($old | path exists) {
        mkdir ($new | path dirname)
        # a shell started before this run may have written the new file already: keep both, old lines first
        if ($new | path exists) { open --raw $old | append (open --raw $new) | str join | save --force $new } else { mv $old $new }
        rm --force $old
        ^chmod 600 $new
    }
    # a cache, rebuilt by the next shell's compinit
    dumps | each { rm --force $in } | ignore
}

export def down []: nothing -> nothing {
    let new = new-history
    if ($new | path exists) and not (old-history | path exists) { mv $new (old-history) }
}
