use module.nu *

export const meta = {
    deps: [core/gh]
    inputs: [~/projects ~/.config/tms/config.toml configs/secrets/keys/repositories]
}

const PROJECTS = "projects"
# <spec> [path] [secret] per line: what to clone and where
const REPOSITORIES = "configs/secrets/keys/repositories"
const BARE = [probe]
const ICON = "folder-development"
# a push to github alone must not reach root here through git-sync and dot apply
const DOTFILES_GIT = {"pull.rebase": "false", "pull.ff": "only", "merge.verifySignatures": "true"}

def repository-url [spec: string]: nothing -> string {
    if ($spec =~ '://' or ($spec | str starts-with "git@")) { $spec } else { $"https://github.com/($spec | str replace --regex '\.git$' '').git" }
}

# a token login read by the helper itself, so the token never lands in the url, the remote config or an argv
def credential-helper [token: path]: nothing -> string {
    $"!f\(\) { test \"$1\" != get || { echo username=x-access-token; sed -n \"1s/^/password=/p\" '($token)'; }; }; f"
}

def clone [root: path, line: string]: nothing -> list<record> {
    let fields = $line | split row --regex '\s+'
    let url = repository-url $fields.0
    let dest = $root | path join ($fields | get --optional 1 | default ($url | path basename | str replace --regex '\.git$' ''))
    if ($dest | path exists) { return [] }
    let secret = $fields | get --optional 2
    let auth = if $secret == null { [] } else {
        let token = $env.DOTFILES | path join configs secrets keys $secret
        if not (secret-is-plaintext $token) {
            log-warn $"projects: configs/secrets/keys/($secret) is locked, ($dest | path basename) skipped"
            return []
        }
        # the empty helper first drops gh's, which logs in as another account
        [-c credential.helper= -c $"credential.helper=(credential-helper $token)"]
    }
    # core/ntfy clones the homelab too, after this plan was made: a checkout that appeared since counts as done
    let git = [env GIT_TERMINAL_PROMPT=0 git ...$auth clone --quiet --recurse-submodules $url $dest]
    [(exec $"clone ($dest | path basename)" [sh -c 'test -e "$0/.git" || exec "$@"' $dest ...$git] --creates $dest)]
}

def collections [root: path]: nothing -> list<path> {
    ls $root | where type == dir | get name | where {|dir|
        let repo = ($dir | path join .git | path exists) or ($dir | path join HEAD | path exists)
        not $repo and ((glob ($dir | path join "*" .git) | is-not-empty) or (glob ($dir | path join "*" .bare) | is-not-empty))
    }
}

def bookmarks []: nothing -> list<string> {
    try { open ($nu.home-dir | path join .config tms config.toml) | get bookmarks } catch { [] }
}

def icon-set [root: path]: nothing -> bool {
    (^gio info -a metadata::custom-icon-name $root | complete | get stdout) =~ $"custom-icon-name: ($ICON)"
}

export def link [cfg: record] {
    if not (profile-has identity) { return [] }
    let root = $nu.home-dir | path join $PROJECTS
    let repositories = $env.DOTFILES | path join $REPOSITORIES
    let lines = if (secret-is-plaintext $repositories) {
        open --raw $repositories | lines | each { split row "#" | first | str trim } | where $it != ""
    } else { [] }
    let dotfiles = $root | path join arch-dotfiles
    let marked = bookmarks
    [
        (exec projects-dir [mkdir -p $root] --creates $root)
        (file-text ($root | path join .directory) $"[Desktop Entry]\nIcon=($ICON)\n")
        (if (which gio | is-empty) or (($root | path exists) and (icon-set $root)) { [] } else {
            [(exec projects-icon [gio set $root metadata::custom-icon-name $ICON])]
        })
        ($BARE | each {|b| exec $"bare ($b)" [git init --quiet --bare ($root | path join $b)] --creates ($root | path join $b HEAD) })
        ($lines | each {|l| clone $root $l } | flatten)
        (if ($root | path exists) { collections $root | where $it not-in $marked | each {|d| exec $"bookmark ($d | path basename)" [tms bookmark $d] } } else { [] })
        (if ($dotfiles | path join .git | path exists) {
            $DOTFILES_GIT | items {|key, value|
                let current = ^git -C $dotfiles config --get $key | complete | get stdout | str trim
                if $current == $value { null } else { exec $"dotfiles ($key)" [git -C $dotfiles config $key $value] }
            } | compact
        } else { [] })
    ]
}
