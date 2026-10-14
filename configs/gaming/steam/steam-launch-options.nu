#!/usr/bin/env -S nu --no-config-file
# gamemode and MangoHud engage per game through its launch option in steam's localconfig.vdf, so installed games
# without one get `gamemoderun mangohud %command%`: steam-launch.nu cannot preload them into the client (it breaks the
# webhelper websocket) and the global MANGOHUD=1 is vulkan-only. a game whose option the user set is never touched.
# steam rewrites localconfig.vdf from memory when it exits, so this refuses while steam is open; the file is backed up
# before the first write

const LAUNCH_OPTIONS_DEFAULT = "gamemoderun mangohud %command%"
const APPS_PATH = [UserLocalConfigStore Software Valve Steam apps]
# steam holds localconfig.vdf open and overwrites it on exit
const STEAM_PROCESSES = [steam steamwebhelper]
const BACKUP_SUFFIX = ".dotfiles-bak"
# a vdf token: a quoted string (escapes kept as written, so a round trip is exact) or a brace
const TOKEN = '"(?<s>(?:[^"\\]|\\.)*)"|(?<b>[{}])'

def steam-root []: nothing -> path {
    $env.STEAM_ROOT? | default ($nu.home-dir | path join .local share Steam)
}

# an object is a list of {k, v}, v a string or a nested object: keeps order and steam's duplicate keys
def vdf-object [tokens: list, start: int]: nothing -> record {
    mut i = $start
    mut pairs = []
    while $i < ($tokens | length) and ($tokens | get $i | get b) != "}" {
        let key = $tokens | get $i | get s
        if ($tokens | get ($i + 1) | get b) == "{" {
            let nested = vdf-object $tokens ($i + 2)
            $pairs = $pairs | append {k: $key, v: $nested.pairs}
            $i = $nested.next + 1
        } else {
            $pairs = $pairs | append {k: $key, v: ($tokens | get ($i + 1) | get s)}
            $i = $i + 2
        }
    }
    {pairs: $pairs, next: $i}
}

def vdf-parse []: string -> list {
    let text = $in
    if ($text | str replace --all --regex $TOKEN "" | str trim) != "" { error make {msg: "not plain quoted vdf"} }
    (vdf-object ($text | parse --regex $TOKEN) 0).pairs
}

# vdf's pretty dump: tab indented, braces on their own lines
def vdf-dump [pairs: list, level: int = 0]: nothing -> string {
    let indent = "" | fill --character "\t" --width $level
    $pairs | each {|p|
        if ($p.v | describe) == string {
            $"($indent)\"($p.k)\" \"($p.v)\"\n"
        } else {
            $"($indent)\"($p.k)\"\n($indent){\n(vdf-dump $p.v ($level + 1))($indent)}\n"
        }
    } | str join
}

# steam's keys compare case-insensitively
def vdf-get [pairs: list, key: string]: nothing -> any {
    $pairs | where ($it.k | str lowercase) == ($key | str lowercase) | get --optional 0.v
}

def vdf-update [pairs: list, path: list<string>, change: closure]: nothing -> list {
    if ($path | is-empty) { return (do $change $pairs) }
    let key = $path.0 | str lowercase
    $pairs | each {|p|
        if ($p.k | str lowercase) != $key or ($p.v | describe) == string { return $p }
        $p | update v (vdf-update $p.v ($path | skip 1) $change)
    }
}

# appids with a manifest on disk, across every library folder
def appids-installed []: nothing -> list<string> {
    let folders = steam-root | path join steamapps libraryfolders.vdf
    let libraries = try {
        vdf-get (open --raw $folders | vdf-parse) libraryfolders | each { vdf-get $in.v path } | compact
    } catch { [] }
    $libraries | prepend (steam-root) | each { glob ($in | path join steamapps "appmanifest_*.acf") } | flatten
        | each { path basename | parse "appmanifest_{id}.acf" | get 0.id } | where $it =~ '^\d+$' | uniq
}

def apps-fill [installed: list<string>]: list -> list {
    each {|app|
        if $app.k not-in $installed or ($app.v | describe) == string { return $app }
        let existing = vdf-get $app.v LaunchOptions
        # a user customization wins; only an absent or empty option is filled
        if $existing != null and ($existing | str trim) != "" { return $app }
        let options = if ($app.v | any { $in.k == LaunchOptions }) {
            $app.v | each { if $in.k == LaunchOptions { $in | update v $LAUNCH_OPTIONS_DEFAULT } else { $in } }
        } else { $app.v | append {k: LaunchOptions, v: $LAUNCH_OPTIONS_DEFAULT} }
        $app | update v $options
    }
}

def localconfig-process [file: path, installed: list<string>]: nothing -> bool {
    let config = try { open --raw $file | vdf-parse } catch {|e|
        print --stderr $"steam-launch-options: cannot read ($file): ($e.msg)"
        null
    }
    if $config == null { return false }
    let filled = vdf-update $config $APPS_PATH {|apps| $apps | apps-fill $installed }
    if $filled == $config { return true }
    let backup = $file + $BACKUP_SUFFIX
    if not ($backup | path exists) { cp --preserve [mode timestamps] $file $backup }
    let tmp = $"($file).($nu.pid).tmp"
    vdf-dump $filled | save --force $tmp
    mv --force $tmp $file
    print $"steam-launch-options: set '($LAUNCH_OPTIONS_DEFAULT)' on new games in ($file)"
    true
}

def main []: nothing -> nothing {
    let uid = ^id -u | str trim
    if ($STEAM_PROCESSES | any {|p| (do { ^pgrep -u $uid -x $p } | complete).exit_code == 0 }) {
        let why = "it overwrites localconfig.vdf on exit; close Steam and rerun"
        print --stderr $"steam-launch-options: Steam is open, skipping \(($why)\)"
        return
    }
    let configs = glob (steam-root | path join userdata "*" config localconfig.vdf)
    if ($configs | is-empty) { return }
    let installed = appids-installed
    if ($installed | is-empty) { return }
    if not ($configs | each { localconfig-process $in $installed } | all { $in }) { exit 1 }
}
