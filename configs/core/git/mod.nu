use module.nu *

export const meta = {packages: {pacman: [git git-delta]}, inputs: [/usr/bin/mergiraf /usr/bin/jj /usr/bin/git-lfs]}

# ~/.gitconfig stays the person's and gh's (credential helpers); git reads this one first
const CONFIG_DIR = ".config/git"
# delta's light/dark line tint, rewritten per theme (syntax-theme ansi follows the 16 terminal colours by itself)
const DELTA_THEME = ".cache/wal/delta.gitconfig"
const MERGIRAF_DRIVER = "mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L"

def has [tool: string]: nothing -> bool {
    which $tool | is-not-empty
}

def ini [sections: list<list>]: nothing -> string {
    $sections | each {|s| $s.1 | items {|k, v| $"\t($k) = ($v)" } | prepend $"[($s.0)]" | str join "\n" } | str join "\n" | $"($in)\n"
}

def jj-config [identity: record]: nothing -> string {
    let user = if $identity == null { "" } else { $"[user]\nname = \"($identity.name)\"\nemail = \"($identity.email)\"\n\n" }
    $"#:schema https://docs.jj-vcs.dev/latest/config-schema.json\n\n($user)[ui]\ndefault-command = \"log\"\n"
}

export def link [cfg: record] {
    let dir = $nu.home-dir | path join $CONFIG_DIR
    let identity = if (profile-has identity) { profile-load | select name email } else { null }
    let template = $dir | path join template
    let sections = [
        (if $identity == null { null } else { [user $identity] })
        # no global 'store' helper: gh handles github, and a plaintext store would persist its token too
        [init {defaultBranch: master, templateDir: $template}]
        [pull {rebase: true}]
        [push {autoSetupRemote: true}]
        [core {pager: delta}]
        [interactive {diffFilter: "delta --color-only"}]
        [delta {syntax-theme: ansi, line-numbers: true, navigate: true, side-by-side: true}]
        [merge {conflictStyle: zdiff3}]
        (if (has mergiraf) { ['merge "mergiraf"' {name: mergiraf, driver: $MERGIRAF_DRIVER}] } else { null })
        (if (has git-lfs) {
            ['filter "lfs"' {clean: "git-lfs clean -- %f", smudge: "git-lfs smudge -- %f", process: "git-lfs filter-process", required: true}]
        } else { null })
        [include {path: ($nu.home-dir | path join $DELTA_THEME)}]
    ] | compact
    [
        (file-text ($dir | path join config) (ini $sections))
        # secrets gate: new repos (init/clone) get the gitleaks pre-commit hook; `git init` adds it to an existing one
        (file-copy template/hooks/pre-commit ($template | path join hooks pre-commit) --mode 755)
        (if (has mergiraf) { file-text ($dir | path join attributes) $"(^mergiraf languages --gitattributes)\n" } else { [] })
        (if (has jj) { file-text ($nu.home-dir | path join .config jj config.toml) (jj-config $identity) } else { [] })
        # on PATH, invoked bare by tmux/herdr/nvim/viewers
        (link-commands wtree.nu)
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-load
    if $p == null { return [] }
    file-text ($nu.home-dir | path join $DELTA_THEME) $"[delta]\n    light = ($p.light == '1')\n" --generated
}
