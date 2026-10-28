#!/usr/bin/env -S nu --no-config-file
# Plugins built as the user against hyprland's headers (hyprpm needs root); hyprpm.toml maps commits.

const PLUGINS = [
    {name: "dynamic-cursors", url: "https://github.com/virtcode/hypr-dynamic-cursors", commit: "2a8d0b735328d874a78ca93b2f201649f712a74a"}
]
const PC = "/usr/share/pkgconfig/hyprland.pc"

def cache-dir []: nothing -> path {
    $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join hypr-plugins
}

def out-dir []: nothing -> path {
    $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join hypr-plugins
}

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

def plugin-commit [src: path, hyprland: string]: nothing -> string {
    let pins = open --raw ($src | path join hyprpm.toml) | parse --regex '\["(?<h>[0-9a-f]{40})",\s*"(?<p>[0-9a-f]{40})"\]'
    let hit = $pins | where h == $hyprland | get --optional 0.p
    if $hit == null { error make {msg: $"no plugin pin for hyprland ($hyprland) at the pinned repo commit; bump it in plugins.nu"} }
    $hit
}

def build [plugin: record, hyprland: string]: nothing -> nothing {
    let src = cache-dir | path join $plugin.name
    if not ($src | path join .git | path exists) { ^git clone --quiet $plugin.url $src }
    if (do { ^git -C $src cat-file -e $"($plugin.commit)^{commit}" } | complete).exit_code != 0 { ^git -C $src fetch --quiet origin }
    ^git -C $src checkout --quiet --force $plugin.commit
    ^git -C $src checkout --quiet --force (plugin-commit $src $hyprland)
    do { cd $src; ^make clean | ignore }
    let made = do { cd $src; with-env {PKG_CONFIG_PATH: (pc-dir)} { ^make $"-j(sys cpu | length)" all } } | complete
    if $made.exit_code != 0 { error make {msg: $"($plugin.name) did not build:\n($made.stderr | lines | last 20 | str join "\n")"} }
    mkdir (out-dir)
    cp ($src | path join out $"($plugin.name).so") (so-path $plugin.name $hyprland)
    # builds for other hyprland commits are dead after the upgrade
    glob (out-dir | path join $"($plugin.name)-*.so") | where $it != (so-path $plugin.name $hyprland) | each { rm $in } | ignore
}

# Builds what the installed hyprland lacks, then loads it into the running one when they match.
def main []: nothing -> nothing {
    let hyprland = commit-installed
    if $hyprland == "" { return }
    let failed = $PLUGINS | where {|p|
        if (so-path $p.name $hyprland | path exists) { return false }
        try { build $p $hyprland; false } catch {|e| print --stderr $e.msg; true }
    }
    if ($failed | is-not-empty) {
        ^notify-send -a hyprland "Hyprland plugins did not build" ($failed | get name | str join ", ") | complete | ignore
    }
    if (commit-running) != $hyprland {
        if ($failed | is-not-empty) { exit 1 }
        return
    }
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
    if ($failed | is-not-empty) { exit 1 }
}
