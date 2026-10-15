use module.nu *

# restore checks out pinned commits, and git explains a detached HEAD for every one
const QUIET_GIT = [GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=advice.detachedHead GIT_CONFIG_VALUE_0=false]

export const meta = {
    packages: {
        pacman: [
            luarocks neovide neovim python-pynvim python-tree-sitter-html python-tree-sitter-javascript
            python-tree-sitter-json tree-sitter-cli
        ]
    }
}

const PLUGIN_DIR = ".local/share/nvim/lazy"
const THEME_NAME = ".cache/wal/nvim_theme"

def head-commit [git: path]: nothing -> any {
    let head = open --raw ($git | path join HEAD) | str trim
    if not ($head | str starts-with "ref: ") { return $head }
    let ref = $head | str substring 5..
    let loose = $git | path join $ref
    if ($loose | path exists) { return (open --raw $loose | str trim) }
    open --raw ($git | path join packed-refs) | lines | parse "{sha} {name}" | where name == $ref | get --optional 0.sha
}

def plugins-stale []: nothing -> bool {
    open lazy-lock.json | items {|name, pin|
        let git = $nu.home-dir | path join $PLUGIN_DIR $name .git
        not ($git | path exists) or (head-commit $git) != $pin.commit
    } | any { $in }
}

# a link, not copies: lazy writes lazy-lock.json and zg the spell word lists back into the config dir
export def link [cfg: record] {
    let prefetch = if (plugins-stale) {
        [(exec prefetch [env ...$QUIET_GIT nvim --headless "+Lazy! restore" "+TSInstallSync" "+MasonToolsInstallSync" "+qa"])]
    } else { [] }
    [(file-link . ($nu.home-dir | path join .config nvim))] ++ $prefetch
}

export def theme [cfg: record, wallpaper: string] {
    step theme-push
}

# every running nvim reloads through lua/theme.lua, the entry point startup uses, with the name dot theme wrote
export def theme-push []: nothing -> nothing {
    let name = $nu.home-dir | path join $THEME_NAME
    if not ($name | path exists) { return }
    let expr = $"luaeval\('require\(\"theme\"\).apply\(\"(open --raw $name | str trim)\"\)'\)"
    for server in (glob ($env.XDG_RUNTIME_DIR? | default "/tmp" | path join "nvim.*")) {
        # a socket left by a crashed nvim refuses the connection
        try { ^nvim --server $server --remote-expr $expr o+e>| ignore }
    }
}
