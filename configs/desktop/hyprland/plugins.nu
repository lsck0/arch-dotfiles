#!/usr/bin/env -S nu --no-config-file
# Plugins built as the user against hyprland's headers (hyprpm needs root); hyprpm.toml maps commits.

use ../../../scripts/lib/state.nu [xdg]

const PLUGINS = [
    {name: "dynamic-cursors", url: "https://github.com/virtcode/hypr-dynamic-cursors", commit: "2a8d0b735328d874a78ca93b2f201649f712a74a", dir: "", output: "out/dynamic-cursors.so"}
    {name: "hyprbars", url: "https://github.com/hyprwm/hyprland-plugins", commit: "d2427d4d15b36df40468f5a58bbd67cdba19835d", dir: "hyprbars", output: "hyprbars/hyprbars.so"}
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

# Builds a plugin for this hyprland.
def build [plugin: record, hyprland: string]: nothing -> nothing {
    let src = cache-dir | path join $plugin.name
    if not ($src | path join .git | path exists) { ^git clone --quiet $plugin.url $src }
    if (do { ^git -C $src cat-file -e $"($plugin.commit)^{commit}" } | complete).exit_code != 0 { ^git -C $src fetch --quiet origin }
    ^git -C $src checkout --quiet --force $plugin.commit
    # the map names older hyprlands; one it lacks builds at the pinned commit itself, hyprpm's own rule, and a broken
    # pairing fails the make below instead of loading
    let mapped = plugin-commit $src $hyprland
    if $mapped == null {
        print --stderr $"($plugin.name): no map entry for hyprland ($hyprland), built at the pinned commit"
    }
    let pin = $mapped | default $plugin.commit
    ^git -C $src checkout --quiet --force $pin
    let dir = $src | path join $plugin.dir
    do { cd $dir; ^make clean } | complete | ignore
    let made = do { cd $dir; with-env {PKG_CONFIG_PATH: (pc-dir)} { ^make $"-j(sys cpu | length)" all } } | complete
    if $made.exit_code != 0 { error make {msg: $"($plugin.name) did not build:\n($made.stderr | lines | last 20 | str join "\n")"} }
    mkdir (out-dir)
    cp ($src | path join $plugin.output) (so-path $plugin.name $hyprland)
    # builds for other hyprland commits are dead after the upgrade
    glob (out-dir | path join $"($plugin.name)-*.so") | where $it != (so-path $plugin.name $hyprland) | each { rm $in } | ignore
}

def plugins-missing-for [hyprland: string]: nothing -> list<record> {
    $PLUGINS | where {|p| not (so-path $p.name $hyprland | path exists) }
}

# The plugins the installed hyprland has no build of; building them downloads.
export def plugins-missing []: nothing -> list<string> {
    let hyprland = commit-installed
    if $hyprland == "" { return [] }
    plugins-missing-for $hyprland | get name
}

# Builds what the installed hyprland lacks; false when a build failed.
def plugins-build [hyprland: string]: nothing -> bool {
    let builds = plugins-missing-for $hyprland | each {|p|
        let status = try { build $p $hyprland; "built" } catch {|e| print --stderr $e.msg; "failed" }
        {name: $p.name, status: $status}
    }
    let failed = $builds | where status == failed
    if ($failed | is-not-empty) {
        ^notify-send -a hyprland "Hyprland plugins did not build" ($failed | get name | str join ", ") | complete | ignore
    }
    $failed | is-empty
}

# The built plugins the running hyprland has not loaded, none when it is not the installed one.
def plugins-unloaded-for [hyprland: string]: nothing -> list<record> {
    if $hyprland == "" or (commit-running) != $hyprland { return [] }
    let listed = ^hyprctl plugin list | complete | get stdout
    $PLUGINS | where {|p| (so-path $p.name $hyprland | path exists) and not ($listed | str contains $p.name) }
}

export def plugins-unloaded []: nothing -> list<string> {
    plugins-unloaded-for (commit-installed) | get --optional name | default []
}

# Loads the built plugins into the running hyprland when it is the installed one; local, no download.
def plugins-load [hyprland: string]: nothing -> nothing {
    let results = plugins-unloaded-for $hyprland
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
