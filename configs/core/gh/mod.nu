use module.nu *

export const meta = {backup: {secrets: true}, inputs: [~/.config/gh/hosts.yml ~/.gitconfig]}

const TOKEN = "secrets/github"
const TOKEN_SHAPE = '^gh[a-z]_'
const HOSTS = ".config/gh/hosts.yml"

def token-file []: nothing -> path {
    $env.DOTFILES | path join $TOKEN
}

export def link [cfg: record] {
    let token = token-file
    if (which gh | is-empty) or not (secret-is-plaintext $token) or (open --raw $token) !~ $TOKEN_SHAPE { return [] }
    let helpers = ^git config --global --get-all credential.https://github.com.helper | complete | get stdout
    [
        # file storage: plasma swaps the secret service to ksecretd, which hides a gnome-keyring token
        (if ($nu.home-dir | path join $HOSTS | path exists) { [] } else { step gh-login })
        # git over https to github authenticates through gh from here on
        (if ($helpers | str contains "gh auth git-credential") { [] } else { exec gh-setup-git [gh auth setup-git] })
    ]
}

export def gh-login []: nothing -> nothing {
    open --raw (token-file) | ^gh auth login --insecure-storage --with-token
}

export def backup [cfg: record]: nothing -> nothing {
    let token = do {
        hide-env --ignore-errors GH_TOKEN GITHUB_TOKEN GH_CONFIG_DIR
        ^gh auth token -h github.com | str trim
    }
    # the shape link accepts, so a broken token never replaces the backup
    if $token !~ $TOKEN_SHAPE {
        error make {msg: "gh auth token returned no token, run gh auth login first"}
    }
    $"($token)\n" | save --force (token-file)
}
