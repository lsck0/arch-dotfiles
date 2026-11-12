use module.nu *
use repository.nu [repository-url repository-name]
use ../../core/gh/mod.nu [token-file]

const PROJECTS = "projects"
const REPOSITORIES = "configs/secrets/state/repositories"
const GH_HOSTS = ".config/gh/hosts.yml"
const TMS_CONFIG = ".config/tms/config.toml"

export const meta = {
    # core/gh logs in and core/git wires gh as github's credential helper, before any private repo is cloned
    deps: [core/gh core/git core/tmux]
    inputs: [$"~/($PROJECTS)" $"~/($TMS_CONFIG)" $REPOSITORIES $"~/($GH_HOSTS)"]
}

const BARE = [probe]
const ICON = "folder-development"
const GVFS_METADATA = "/usr/lib/gvfsd-metadata"
# a first clone fetches every submodule's history and the lfs objects (hundreds of MB), past converge's 20min
const CLONE_TIMEOUT = 90min
# a push to github alone must not reach root here through git-sync and dot apply
const DOTFILES_GIT = {"pull.rebase": "false", "pull.ff": "only", "merge.verifySignatures": "true"}

# A helper that reads the token itself, so it never lands in the url, the remote config or an argv.
def credential-helper [token: path]: nothing -> string {
    $"!f\(\) { test \"$1\" != get || { echo username=x-access-token; sed -n \"1s/^/password=/p\" '($token)'; }; }; f"
}

def clone [root: path, line: string]: nothing -> list<record> {
    let fields = $line | split row --regex '\s+'
    let url = repository-url $fields.0
    if $url == null {
        log-warn $"projects: ($fields.0) in ($REPOSITORIES) is neither a url nor user/repo, skipped"
        return []
    }
    let dest = $root | path join ($fields | get --optional 1 | default (repository-name $url))
    if ($dest | path exists) { return [] }
    let secret = $fields | get --optional 2
    # the repos are private: without a github login the clone would only die on a disabled password prompt
    if $secret == null and ($url | str starts-with "https://github.com/") and not ($nu.home-dir | path join $GH_HOSTS | path exists) {
        # with its token core/gh logs in later this run, and the new hosts.yml (an input) plans this module again
        if not (secret-is-plaintext (token-file)) {
            log-warn $"projects: ($dest | path basename) skipped, no github login yet \(core/gh restores it from configs/secrets/keys/gh\)"
        }
        return []
    }
    let auth = if $secret == null { [] } else {
        let token = $env.DOTFILES | path join configs secrets keys $secret
        if not (secret-is-plaintext $token) {
            log-warn $"projects: configs/secrets/keys/($secret) is locked, ($dest | path basename) skipped"
            return []
        }
        # the empty helper first drops gh's, which logs in as another account
        [-c credential.helper= -c $"credential.helper=(credential-helper $token)"]
    }
    # core/ntfy may have cloned the homelab since this plan was made. The clone lands beside dest and moves in whole:
    # one cut off mid-checkout would otherwise stand as dest and satisfy --creates
    let git = [env GIT_TERMINAL_PROMPT=0 git ...$auth clone --quiet --recurse-submodules $url]
    let into = 'test -e "$0/.git" && exit 0; rm -rf "$0.partial" && "$@" "$0.partial" && mv "$0.partial" "$0"'
    [(exec $"clone ($dest | path basename)" [sh -c $into $dest ...$git] --creates $dest --network --timeout $CLONE_TIMEOUT)]
}

def collections [root: path]: nothing -> list<path> {
    ls $root | where type == dir | get name | where {|dir|
        let repo = ($dir | path join .git | path exists) or ($dir | path join HEAD | path exists)
        not $repo and ((glob ($dir | path join "*" .git) | is-not-empty) or (glob ($dir | path join "*" .bare) | is-not-empty))
    }
}

def bookmarks []: nothing -> list<string> {
    try { open ($nu.home-dir | path join $TMS_CONFIG) | get bookmarks } catch { [] }
}

def icon-set [root: path]: nothing -> bool {
    (^gio info -a metadata::custom-icon-name $root | complete | get stdout) =~ $"custom-icon-name: ($ICON)"
}

export def link [cfg: record] {
    if not (owner-unlocked) {
        if (profile-has secrets) { log-warn "projects: secrets locked, owner config not rolled out" }
        return []
    }
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
        (if (which gio | is-not-empty) and ($GVFS_METADATA | path exists) {
            [(exec projects-icon [gio set $root metadata::custom-icon-name $ICON] --done=(($root | path exists) and (icon-set $root)))]
        })
        ($BARE | each {|b| exec $"bare ($b)" [git init --quiet --bare ($root | path join $b)] --creates ($root | path join $b HEAD) })
        ($lines | each {|l| clone $root $l })
        (if ($root | path exists) {
            collections $root | each {|d| exec $"bookmark ($d | path basename)" [tms bookmark $d] --done=($d in $marked) }
        })
        (if ($dotfiles | path join .git | path exists) {
            $DOTFILES_GIT | items {|key, value|
                let current = ^git -C $dotfiles config --get $key | complete | get stdout | str trim
                exec $"dotfiles ($key)" [git -C $dotfiles config $key $value] --done=($current == $value)
            }
        })
    ]
}
