#!/usr/bin/env -S nu --no-config-file
# hyprpm builds the headers and each plugin with cmake, meson and the base-devel toolchain, declared in this module
# hyprpm runs every write to its root-owned store through sudo, a FIDO2 prompt nobody answers at login: build only
# from a terminal, or with --build where sudo asks nothing (the install chain's config stage)

const STORE = "/var/cache/hyprpm"
const PLUGIN = "dynamic-cursors"
const REPOS = [{url: "https://github.com/virtcode/hypr-dynamic-cursors", name: "dynamic-cursors"}]
const BUILT_FOR = ".local/state/hypr-plugins-built-for"

# The installed hyprland's commit (the binary on disk, which the plugins must match after the next login), and the
# running one's; they differ between a package upgrade and the relogin.
def commit-installed []: nothing -> string {
    try { ^Hyprland --version | parse --regex 'at commit (?<c>[0-9a-f]+)' | get 0.c } catch { "" }
}

def commit-running []: nothing -> string {
    try { ^hyprctl version -j | from json | get commit } catch { "" }
}

def built-for []: nothing -> string {
    try { open --raw ($nu.home-dir | path join $BUILT_FOR) | str trim } catch { "" }
}

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
        if (built-for) != (commit-installed) {
            ^notify-send -a hyprpm "Hyprland plugins built for an older Hyprland" "run dot sync (or configs/desktop/hyprland/plugins.nu) from a terminal" | complete | ignore
            return
        }
        if not (loaded) { ^hyprpm reload }
        return
    }
    # headers first: `hyprpm add` refuses to build without them; every hyprland update rebuilds each added repo. Stale
    # against the installed hyprland; built only once the running one is that same hyprland, since hyprpm fetches the
    # running instance's headers: a sync that just upgraded hyprland leaves it stale for the sync after the relogin
    let state = $nu.home-dir | path join $BUILT_FOR
    let commit = commit-installed
    if $commit != "" and (commit-running) not-in ["" $commit] {
        print "note: hyprland was upgraded, its plugins rebuild after the next login (dot sync or plugins.nu)"
        return
    }
    let stale = $commit == "" or (built-for) != $commit
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
