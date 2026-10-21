#!/usr/bin/env -S nu --no-config-file

const PROJECTS = "projects"
const COLOR_ERROR = "1"

def popup-fail [message: string]: nothing -> nothing {
    ^gum style --foreground $COLOR_ERROR $message
    input ""
    exit 1
}

# Clone a git url or user/repo into ~/projects with submodules and open it in the multiplexer.
def main []: nothing -> nothing {
    let typed = try { ^gum input --prompt "❯ " --placeholder "git url or user/repo" --width 60 } catch { "" }
    if $typed == "" { return }
    let url = match $typed {
        $u if $u =~ '://' or ($u | str starts-with "git@") => $u
        $u if $u =~ '/' => $"https://github.com/($u | str replace --regex '\.git$' '').git"
        _ => { popup-fail "need a full URL or user/repo" }
    }
    let name = $url | str replace --regex '\.git$' '' | path basename
    let dest = $nu.home-dir | path join $PROJECTS $name
    if ($dest | path exists) { popup-fail $"($dest) already exists" }
    try {
        ^gum spin --title $"cloning ($name)..." -- git clone --recurse-submodules $url $dest
    } catch { popup-fail "clone failed" }
    if ($env.TMUX? | is-not-empty) {
        let session = $name | str replace --all --regex '[.:]' '_'
        if (do { ^tmux has-session -t $"=($session)" } | complete).exit_code != 0 {
            ^tmux new-session -d -s $session -c $dest
        }
        ^tmux switch-client -t $"=($session)"
    } else if ($"($env.HERDR_SESSION? | default '')($env.HERDR_ENV? | default '')" | is-not-empty) {
        ^herdr-open $dest $name
    } else {
        print $">>> cloned to ($dest)"
        input ""
    }
}
