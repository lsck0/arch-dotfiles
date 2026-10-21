use module.nu *

const QUIET_GIT = [GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=advice.detachedHead GIT_CONFIG_VALUE_0=false]

export const meta = {
    packages: {
        pacman: [
            luarocks namcap neovide neovim python-pynvim python-tree-sitter-html python-tree-sitter-javascript
            python-tree-sitter-json tree-sitter-cli
        ]
    }
}

const PLUGIN_DIR = ".local/share/nvim/lazy"
const THEME_NAME = ".cache/wal/nvim_theme"

# Null for a partial clone (interrupted restore) that lacks HEAD, the loose ref and packed-refs alike.
def head-commit [git: path]: nothing -> any {
    let head_file = $git | path join HEAD
    if not ($head_file | path exists) { return null }
    let head = open --raw $head_file | str trim
    if not ($head | str starts-with "ref: ") { return $head }
    let ref = $head | str substring 5..
    let loose = $git | path join $ref
    if ($loose | path exists) { return (open --raw $loose | str trim) }
    let packed = $git | path join packed-refs
    if not ($packed | path exists) { return null }
    open --raw $packed | lines | parse "{sha} {name}" | where name == $ref | get --optional 0.sha
}

def plugins-stale []: nothing -> list<string> {
    open lazy-lock.json | items {|name, pin|
        let git = $nu.home-dir | path join $PLUGIN_DIR $name .git
        if not ($git | path exists) or (head-commit $git) != $pin.commit { $name }
    } | compact
}

# a link, not copies: lazy writes lazy-lock.json and zg the spell word lists back into the config dir
export def link [cfg: record] {
    let restore = if (plugins-stale | is-not-empty) { ["+Lazy! restore" "+TSInstallSync" "+MasonToolsInstallSync"] } else { [] }
    [
        (file-link . ($nu.home-dir | path join .config nvim))
        (step prefetch ...$restore)
    ]
}

# Restore the plugins; nvim exits 0 even when every fetch failed, so the pins tell.
export def prefetch [...restore: string]: nothing -> nothing {
    ^env ...$QUIET_GIT nvim --headless ...$restore "+qa"
    let stale = plugins-stale
    if ($stale | is-not-empty) {
        error make {msg: $"($stale | length) plugins are not at their lazy-lock.json pin after the restore: ($stale | str join ' ')"}
    }
}

export def theme [cfg: record, wallpaper: string] {
    step theme-push
}

export def theme-push []: nothing -> nothing {
    let name = $nu.home-dir | path join $THEME_NAME
    if not ($name | path exists) { return }
    let expr = $"luaeval\('require\(\"theme\"\).apply\(\"(open --raw $name | str trim)\"\)'\)"
    for server in (glob ($env.XDG_RUNTIME_DIR? | default "/tmp" | path join "nvim.*")) {
        try { ^nvim --server $server --remote-expr $expr o+e>| ignore }
    }
}
