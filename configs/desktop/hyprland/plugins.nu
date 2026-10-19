#!/usr/bin/env -S nu --no-config-file
# hyprpm sudoes every call until its store exists, a FIDO2 prompt nobody answers at login: build only from a terminal

const STORE = "/var/cache/hyprpm"
const PLUGIN = "dynamic-cursors"
const REPOS = [{url: "https://github.com/virtcode/hypr-dynamic-cursors", name: "dynamic-cursors"}]
const BUILT_FOR = ".local/state/hypr-plugins-built-for"

def loaded []: nothing -> bool {
    ^hyprctl plugin list | complete | get stdout | str lowercase | str contains $PLUGIN
}

def --wrapped hyprpm-yes [...args: string]: nothing -> bool {
    (^yes | ^hyprpm ...$args | complete).exit_code == 0
}

def main [] {
    if (which hyprpm | is-empty) { return }
    if not (is-terminal --stdout) {
        # a built .so, not the store dir: any hyprpm call creates an empty headersRoot, and reloading that fails
        if (glob $"($STORE)/($env.USER)/*/*.so" | is-empty) {
            ^notify-send -a hyprpm "Hyprland plugins not built" "run system-update (or configs/desktop/hyprland/plugins.nu) from a terminal" | complete | ignore
            return
        }
        if not (loaded) { ^hyprpm reload }
        return
    }
    # headers first: `hyprpm add` refuses to build without them; every hyprland update rebuilds each added repo
    let state = $nu.home-dir | path join $BUILT_FOR
    let commit = try { ^hyprctl version -j | from json | get commit } catch { "" }
    let stale = $commit == "" or (try { open --raw $state | str trim } catch { "" }) != $commit
    let updated = $stale and (hyprpm-yes update -f)
    if $updated {
        mkdir ($state | path dirname)
        $"($commit)\n" | save --force $state
    }
    let listed = ^hyprpm list | complete | get stdout | str lowercase
    let added = $REPOS | where {|r| not ($listed | str contains $"repository ($r.name) ") } | each {|r| hyprpm-yes add $r.url }
    if $updated or ($added | is-not-empty) or not (loaded) {
        ^hyprpm enable $PLUGIN | complete | ignore
        ^hyprpm reload
    }
}
