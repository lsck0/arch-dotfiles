#!/usr/bin/env -S nu --no-config-file
# hyprpm builds the headers and each plugin with cmake, meson and the base-devel toolchain, declared in this module
# hyprpm runs every write to its root-owned store through sudo, a FIDO2 prompt nobody answers at login: build only
# from a terminal, or with --build where sudo asks nothing (the install chain's config stage)

const STORE = "/var/cache/hyprpm"
const PLUGIN = "dynamic-cursors"
const REPOS = [{url: "https://github.com/virtcode/hypr-dynamic-cursors", name: "dynamic-cursors"}]
const BUILT_FOR = ".local/state/hypr-plugins-built-for"

def loaded []: nothing -> bool {
    ^hyprctl plugin list | complete | get stdout | str lowercase | str contains $PLUGIN
}

# a failure prints hyprpm's own output, the build log is the only clue to a missing header or toolchain
def --wrapped hyprpm-yes [...args: string]: nothing -> bool {
    let run = ^yes | ^hyprpm ...$args | complete
    if $run.exit_code != 0 { print --stderr $"hyprpm ($args | str join ' ') failed:\n($run.stdout)($run.stderr)" }
    $run.exit_code == 0
}

def main [--build] {
    if (which hyprpm | is-empty) { return }
    if not $build and not (is-terminal --stdout) {
        # a built .so, not the store dir: any hyprpm call creates an empty headersRoot, and reloading that fails
        if (glob $"($STORE)/($env.USER)/*/*.so" | is-empty) {
            ^notify-send -a hyprpm "Hyprland plugins not built" "run dot sync (or configs/desktop/hyprland/plugins.nu) from a terminal" | complete | ignore
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
    # a failed rebuild leaves the old .so in place, so the exit code, not the files, tells the caller
    let failed = ($stale and not $updated) or (false in $added)
    if $updated or ($added | is-not-empty) or not (loaded) {
        ^hyprpm enable $PLUGIN | complete | ignore
        # no session yet in the install chain: the login's plugins.nu loads it
        let sig = $env.HYPRLAND_INSTANCE_SIGNATURE? | default ""
        if $sig != "" and ($env.XDG_RUNTIME_DIR | path join hypr $sig .socket.sock | path exists) { ^hyprpm reload }
    }
    if $failed { exit 1 }
}
