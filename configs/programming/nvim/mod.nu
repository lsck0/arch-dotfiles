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
# lazy skips a plugin outright when its spec's cond is false (image.nvim: only in a kitty-protocol terminal);
# headless install has no such terminal, so lazy-lock.json's pin for it is never meant to be cloned there
const COND_LUA = '
local cfg = require("lazy.core.config")
local names = {}
for name, p in pairs(cfg.plugins) do
    local c = p.cond
    local ok = true
    if type(c) == "function" then
        local success, result = pcall(c, p)
        ok = (not success) or (result and true or false)
    elseif c ~= nil then
        ok = c and true or false
    end
    if ok then table.insert(names, name) end
end
io.write(table.concat(names, "\n"))
'

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

# Plugins lazy actually wants installed right now; a false `cond` (e.g. terminal_graphics outside kitty/ghostty)
# means it is correctly absent, not stale.
def plugins-enabled []: nothing -> list<string> {
    ^env ...$QUIET_GIT nvim --headless -c $"lua ($COND_LUA)" -c "qa" | lines
}

def plugins-stale []: nothing -> list<string> {
    let enabled = plugins-enabled
    open lazy-lock.json | items {|name, pin|
        if $name not-in $enabled { return null }
        let git = $nu.home-dir | path join $PLUGIN_DIR $name .git
        if not ($git | path exists) or (head-commit $git) != $pin.commit { $name }
    } | compact
}

# What lua/lib/{mason_packages,treesitter_parsers}.lua name and is not installed, as "<kind> <name>" lines: a
# failed download or a newly added name is installed on the next apply, not left to nvim's own start-up check
const MISSING_LUA = '
local data = vim.fn.stdpath("data")
local function report(kind, names, path)
    for _, name in ipairs(names) do
        if not vim.uv.fs_stat(data .. path:format(name)) then
            io.write(kind, " ", name, "\n")
        end
    end
end
report("mason", require("lib.mason_packages"), "/mason/packages/%s/mason-receipt.json")
report("parser", require("lib.treesitter_parsers"), "/site/parser/%s.so")
'

def tools-missing []: nothing -> table<kind: string, name: string> {
    ^nvim --headless -c $"lua ($MISSING_LUA)" -c "qa" | lines | parse "{kind} {name}"
}

# a link, not copies: lazy writes lazy-lock.json and zg the spell word lists back into the config dir
export def link [cfg: record] {
    let restore = if (plugins-stale | is-not-empty) {
        ["+Lazy! restore" "+TSInstallSync" "+MasonToolsInstallSync"]
    } else {
        let kinds = tools-missing | get kind | uniq
        [
            ...(if "parser" in $kinds { ["+TSInstallSync"] } else { [] })
            ...(if "mason" in $kinds { ["+MasonToolsInstallSync"] } else { [] })
        ]
    }
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
    let missing = tools-missing
    if ($missing | is-not-empty) {
        error make {msg: $"($missing | length) tools are not installed after the restore \(:MasonLog, :checkhealth nvim-treesitter\): ($missing | each { $'($in.kind)/($in.name)' } | str join ' ')"}
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
