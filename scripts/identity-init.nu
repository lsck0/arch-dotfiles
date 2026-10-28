#!/usr/bin/env -S nu --no-config-file

const SCRIPTS = path self | path expand | path dirname
use ($SCRIPTS | path join lib usage.nu) [die]

const TEMPLATE = $SCRIPTS | path dirname | path join configs programming identity envrc
const ENVRC_LINE = "source_env_if_exists .identity/envrc"

def envrc-line-add [envrc: path]: nothing -> nothing {
    let text = if ($envrc | path exists) { open --raw $envrc } else { "" }
    if $ENVRC_LINE in ($text | lines) {
        let last = $text | lines | where $it !~ '^\s*(#.*)?$' | last
        if $last != $ENVRC_LINE {
            print --stderr $"warning: lines after '($ENVRC_LINE)' in ($envrc) can override the identity"
        }
        return
    }
    let separator = if $text == "" or ($text | str ends-with "\n") { "" } else { "\n" }
    $"($separator)($ENVRC_LINE)\n" | save --append $envrc
}

# Give a repository its own customer identity, see configs/programming/identity/envrc.
def main [repo_dir?: path]: nothing -> nothing {
    let repo = $repo_dir | default "." | path expand
    if ($repo | path type) != dir { die --misuse $"($repo_dir) is not a directory" }
    if (which direnv | is-empty) { die "direnv missing: dot apply --packages" }
    let identity = $repo | path join .identity
    mkdir $identity
    ^chmod 700 $identity
    "*\n" | save --force ($identity | path join .gitignore)
    ^install -m 644 $TEMPLATE ($identity | path join envrc)
    let env_file = $identity | path join env
    if not ($env_file | path exists) {
        ^install -m 600 /dev/null $env_file
        let name = do { ^git config --global user.name } | complete | get stdout | str trim
            | str replace --all '\' '\\' | str replace --all '"' '\"' | str replace --all '$' '\$' | str replace --all '`' '\`'
        [
            $'GIT_NAME="($name)"'
            "GIT_EMAIL="
            "# gpg key id from .identity/gnupg, signs git and jj commits"
            "GIT_SIGNING_KEY="
            ""
            "# TF_TOKEN_app_terraform_io="
        ] | str join "\n" | $"($in)\n" | save --force $env_file
        print $"set GIT_EMAIL in ($env_file)"
    }
    envrc-line-add ($repo | path join .envrc)
    print $"run 'direnv allow ($repo)'"
}
