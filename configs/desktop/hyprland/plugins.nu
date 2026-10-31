#!/usr/bin/env -S nu --no-config-file
# Plugins built as the user against hyprland's headers (hyprpm needs root); hyprpm.toml maps commits.

use ../../../scripts/lib/state.nu [xdg]

const PLUGINS = [
    {name: "dynamic-cursors", url: "https://github.com/virtcode/hypr-dynamic-cursors", commit: "2a8d0b735328d874a78ca93b2f201649f712a74a"}
]
const PC = "/usr/share/pkgconfig/hyprland.pc"

def cache-dir []: nothing -> path { xdg cache hypr-plugins }

def out-dir []: nothing -> path { xdg data hypr-plugins }

# Installed vs running hyprland commit: they differ between an upgrade and the relogin.
def commit-installed []: nothing -> string {
    try { ^Hyprland --version | parse --regex 'at commit (?<c>[0-9a-f]+)' | get 0.c } catch { "" }
}

def commit-running []: nothing -> string {
    try { ^hyprctl version -j | from json | get commit } catch { "" }
}

def so-path [name: string, hyprland: string]: nothing -> path { out-dir | path join $"($name)-($hyprland).so" }

# the package's pc file with its own prefix: an earlier hyprpm may have pointed it at its root store
def pc-dir []: nothing -> path {
    let dir = cache-dir | path join pkgconfig
    mkdir $dir
    open --raw $PC | str replace --regex '(?m)^prefix=.*$' 'prefix=/usr/include' | save --force ($dir | path join hyprland.pc)
    $dir
}

# The plugin commit the checked-out map names for this hyprland, null when it has none.
def plugin-commit [src: path, hyprland: string]: nothing -> any {
    let pins = open --raw ($src | path join hyprpm.toml) | parse --regex '\["(?<h>[0-9a-f]{40})",\s*"(?<p>[0-9a-f]{40})"\]'
    $pins | where h == $hyprland | get --optional 0.p
}

# Builds a plugin for this hyprland; false when the pinned commit has no map for it yet.
def build [plugin: record, hyprland: string]: nothing -> bool {
    let src = cache-dir | path join $plugin.name
    if not ($src | path join .git | path exists) { ^git clone --quiet $plugin.url $src }
    if (do { ^git -C $src cat-file -e $"($plugin.commit)^{commit}" } | complete).exit_code != 0 { ^git -C $src fetch --quiet origin }
    ^git -C $src checkout --quiet --force $plugin.commit
    let pin = plugin-commit $src $hyprland
    if $pin == null {
        print --stderr $"($plugin.name): no pin for hyprland ($hyprland) at the pinned commit, bump PLUGINS in plugins.nu"
        return false
    }
    ^git -C $src checkout --quiet --force $pin
    do { cd $src; ^make clean | ignore }
    let made = do { cd $src; with-env {PKG_CONFIG_PATH: (pc-dir)} { ^make $"-j(sys cpu | length)" all } } | complete
    if $made.exit_code != 0 { error make {msg: $"($plugin.name) did not build:\n($made.stderr | lines | last 20 | str join "\n")"} }
    mkdir (out-dir)
    cp ($src | path join out $"($plugin.name).so") (so-path $plugin.name $hyprland)
    # builds for other hyprland commits are dead after the upgrade
    glob (out-dir | path join $"($plugin.name)-*.so") | where $it != (so-path $plugin.name $hyprland) | each { rm $in } | ignore
    true
}

# The plugins the installed hyprland has no build of; building them downloads.
export def plugins-missing []: nothing -> list<string> {
    let hyprland = commit-installed
    if $hyprland == "" { return [] }
    $PLUGINS | where {|p| not (so-path $p.name $hyprland | path exists) } | get name
}

# Builds what the installed hyprland lacks; false when a build failed.
def plugins-build [hyprland: string]: nothing -> bool {
    let builds = $PLUGINS | where {|p| not (so-path $p.name $hyprland | path exists) } | each {|p|
        let status = try { if (build $p $hyprland) { "built" } else { "unpinned" } } catch {|e| print --stderr $e.msg; "failed" }
        {name: $p.name, status: $status}
    }
    let failed = $builds | where status == failed
    let unpinned = $builds | where status == unpinned
    if ($unpinned | is-not-empty) {
        ^notify-send -a hyprland -u low "Hyprland plugins off: no build for this Hyprland" $"($unpinned | get name | str join ', '): bump PLUGINS in plugins.nu" | complete | ignore
    }
    if ($failed | is-not-empty) {
        ^notify-send -a hyprland "Hyprland plugins did not build" ($failed | get name | str join ", ") | complete | ignore
    }
    $failed | is-empty
}

# Loads the built plugins into the running hyprland when it is the installed one; local, no download.
def plugins-load [hyprland: string]: nothing -> nothing {
    if (commit-running) != $hyprland { return }
    let listed = ^hyprctl plugin list | complete | get stdout
    let results = $PLUGINS | where {|p| (so-path $p.name $hyprland | path exists) and not ($listed | str contains $p.name) }
        | each {|p| {name: $p.name, exit_code: (^hyprctl plugin load (so-path $p.name $hyprland) | complete | get exit_code)} }
    let loaded = $results | where exit_code == 0
    let load_failed = $results | where exit_code != 0
    if ($load_failed | is-not-empty) {
        ^notify-send -a hyprland "Hyprland plugins did not load" ($load_failed | get name | str join ", ") | complete | ignore
    }
    # plugin options are only accepted once the plugin is in, so the config is read again
    if ($loaded | is-not-empty) { ^hyprctl reload | ignore }
}

# Builds what the installed hyprland lacks (git and make, the network).
def "main build" []: nothing -> nothing {
    let hyprland = commit-installed
    if $hyprland != "" and not (plugins-build $hyprland) { exit 1 }
}

# Loads the built plugins into the running hyprland.
def "main load" []: nothing -> nothing {
    let hyprland = commit-installed
    if $hyprland != "" { plugins-load $hyprland }
}

# Builds what the installed hyprland lacks, then loads it into the running one when they match.
def main []: nothing -> nothing {
    let hyprland = commit-installed
    if $hyprland == "" { return }
    let built = plugins-build $hyprland
    plugins-load $hyprland
    if not $built { exit 1 }
}
