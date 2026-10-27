use module.nu *

export const meta = {deps: [core/wallust], packages: {pacman: [git git-delta]}, inputs: [/usr/bin/mergiraf /usr/bin/jj /usr/bin/git-lfs /usr/bin/gh]}

const CONFIG_DIR = ".config/git"
const DELTA_THEME = ".cache/wal/delta.gitconfig"
const MERGIRAF_DRIVER = "mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L"
const GH_HELPER = "!/usr/bin/gh auth git-credential"
const GH_HOSTS = [github.com gist.github.com]

def has [tool: string]: nothing -> bool {
    which $tool | is-not-empty
}

# Renders [section, record] pairs as git ini; a list value repeats its key, one line per item.
def ini [sections: list<list>]: nothing -> string {
    $sections | each {|s|
        $s.1 | items {|k, v| [$v] | flatten | each {|one| $"\t($k) = ($one)" } } | flatten | prepend $"[($s.0)]" | str join "\n"
    } | str join "\n" | $"($in)\n"
}

def jj-config [identity: oneof<record, nothing>]: nothing -> string {
    let user = if $identity == null { "" } else { $"[user]\nname = \"($identity.name)\"\nemail = \"($identity.email)\"\n\n" }
    $"#:schema https://docs.jj-vcs.dev/latest/config-schema.json\n\n($user)[ui]\ndefault-command = \"log\"\n"
}

export def link [cfg: record] {
    let dir = $nu.home-dir | path join $CONFIG_DIR
    let identity = if (profile-has secrets) { profile-load | select name email } else { null }
    let template = $dir | path join template
    let sections = [
        (if $identity == null { null } else { [user $identity] })
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
        [include {path: [($nu.home-dir | path join $DELTA_THEME) ($dir | path join forgejo.inc)]}]
        # the empty helper clears any inherited one, then gh answers
        ...(if (has gh) { $GH_HOSTS | each {|host| [$'credential "https://($host)"' {helper: ["" $GH_HELPER]}] } } else { [] })
    ] | compact
    [
        (file-text ($dir | path join config) (ini $sections))
        (file-copy template/hooks/pre-commit ($template | path join hooks pre-commit) --mode 755)
        (if (has mergiraf) { file-text ($dir | path join attributes) $"(^mergiraf languages --gitattributes)\n" } else { [] })
        (if (has jj) { file-text (xdg config jj config.toml) (jj-config $identity) } else { [] })
        (link-commands wtree.nu)
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-load
    if $p == null { return [] }
    file-text ($nu.home-dir | path join $DELTA_THEME) $"[delta]\n    light = ($p.light == '1')\n" --generated
}
