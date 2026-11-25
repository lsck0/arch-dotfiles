use module.nu *
use ../wallust/scripts/editor.nu [editor-roles]
use ../wallust/scripts/palette.nu [palette-rgb]

export const meta = {deps: [core/cli core/tmux core/wallust], packages: {pacman: [git git-delta git-lfs]}, inputs: [/usr/bin/mergiraf /usr/bin/jj /usr/bin/gh]}

export const options = {
    default_branch: {
        type: string
        default: master
        doc: "Branch git init starts with, init.defaultBranch"
        label: "Default branch"
        scope: user
    }
    pull_rebase: {
        type: bool
        default: true
        doc: "git pull rebases local commits instead of merging, pull.rebase"
        label: "Pull rebases"
        scope: user
    }
    side_by_side: {
        type: bool
        default: true
        doc: "delta shows diffs in two columns, delta.side-by-side"
        label: "Side-by-side diffs"
        scope: user
    }
    # no quote, backslash, comment sign or line break: the value goes into git's ini and jj's toml unescaped
    user_name: {
        type: "string?"
        default: null
        pattern: '^[^"\\#;\n]+$'
        doc: "Commit author name of a login that is not the owner, user.name; unset takes its profile's name"
        label: "Author name"
        scope: user
    }
    user_email: {
        type: "string?"
        default: null
        pattern: '^[^"\\#;\s]+@[^"\\#;\s]+$'
        doc: "Commit author email of a login that is not the owner, user.email; unset takes its profile's email"
        label: "Author email"
        scope: user
    }
}

const DELTA_THEME = "wal/delta.gitconfig"
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
    } | to text
}

def jj-config [identity: oneof<record, nothing>]: nothing -> string {
    let user = if $identity == null { "" } else { $"[user]\nname = \"($identity.name)\"\nemail = \"($identity.email)\"\n\n" }
    $"#:schema https://docs.jj-vcs.dev/latest/config-schema.json\n\n($user)[ui]\ndefault-command = \"log\"\n"
}

export def link [cfg: record] {
    let dir = xdg config git
    # the owner's identity rolls out only when the owner is actually unlocked (profile AND the YubiKey), never on profile
    # selection alone; any other login's is its own: the author options, else a profile without the secrets capability
    let profile = profile-load | select name email
    let fallback = if (profile-has secrets) { {name: "", email: ""} } else { $profile }
    let own = {name: ($cfg.user_name | default $fallback.name), email: ($cfg.user_email | default $fallback.email)}
    let identity = if (owner-unlocked) { $profile } else if $own.name != "" and $own.email != "" { $own } else { null }
    let template = $dir | path join template
    let sections = [
        (if $identity != null { [user $identity] })
        [init {defaultBranch: $cfg.default_branch, templateDir: $template}]
        [pull {rebase: $cfg.pull_rebase}]
        [push {autoSetupRemote: true}]
        [core {pager: delta}]
        [interactive {diffFilter: "delta --color-only"}]
        [delta {syntax-theme: wal, line-numbers: true, navigate: true, side-by-side: $cfg.side_by_side}]
        [merge {conflictStyle: zdiff3}]
        (if (has mergiraf) { ['merge "mergiraf"' {name: mergiraf, driver: $MERGIRAF_DRIVER}] })
        (if (has git-lfs) {
            ['filter "lfs"' {clean: "git-lfs clean -- %f", smudge: "git-lfs smudge -- %f", process: "git-lfs filter-process", required: true}]
        })
        [include {path: [(xdg cache $DELTA_THEME) ($dir | path join forgejo.inc)]}]
        # the empty helper clears any inherited one, then gh answers
        ...(if (has gh) { $GH_HOSTS | each {|host| [$'credential "https://($host)"' {helper: ["" $GH_HELPER]}] } } else { [] })
    ] | compact
    [
        (file-text ($dir | path join config) (ini $sections))
        (file-copy config/template/hooks/pre-commit ($template | path join hooks pre-commit) --mode 755)
        (if (has mergiraf) { file-text ($dir | path join attributes) $"(^mergiraf languages --gitattributes)\n" })
        (if (has jj) { file-text (xdg config jj config.toml) (jj-config $identity) })
        (link-commands scripts/wtree.nu)
        (shell-aliases git)
    ]
}

# On the raw background: delta draws in the terminal.
export def theme [cfg: record, wallpaper: string] {
    let p = palette-rgb git
    if $p == null { return [] }
    let r = $p | editor-roles $p.bg
    let keys = {
        light: $r.light
        plus-style: $"syntax ($r.diff_add)"
        plus-emph-style: $"syntax ($r.diff_add_text)"
        minus-style: $"syntax ($r.diff_delete)"
        minus-emph-style: $"syntax ($r.diff_delete_text)"
        line-numbers-plus-style: $r.added
        line-numbers-minus-style: $r.removed
        line-numbers-zero-style: $r.line_number
        line-numbers-left-style: $r.border
        line-numbers-right-style: $r.border
        file-style: $"($r.function) bold"
        file-decoration-style: $"($r.border) ul"
        hunk-header-style: "file line-number syntax"
        hunk-header-decoration-style: $"($r.border) box"
        hunk-header-file-style: $r.function
        hunk-header-line-number-style: $r.line_number
        commit-decoration-style: $"($r.keyword) box"
        blame-palette: $"($r.bg) ($r.surface)"
        merge-conflict-ours-diff-header-style: $"($r.added) bold"
        merge-conflict-theirs-diff-header-style: $"($r.changed) bold"
    }
    let body = $keys | items {|k, v| $"    ($k) = ($v | to json)" } | str join "\n"
    file-text (xdg cache $DELTA_THEME) $"[delta]\n($body)\n" --generated
}
