#!/usr/bin/env -S nu --no-config-file
# installed as dalamud's installer would: dalamud never installs a collection's plugins by itself

const MAIN_REPO_URL = "https://kamori.goats.dev/Plugin/PluginMaster"
const KEPT = [
    Disabled Testing InstalledFromUrl WorkingPluginId IsThirdParty IsHide DownloadLinkInstall DownloadLinkTesting
    DownloadLinkUpdate DownloadCount LastUpdate TestingAssemblyVersion TestingDalamudApiLevel
]
const INDEX_MAX_AGE = 10min

def main [manifest: path, plugins: path]: nothing -> nothing {
    let old = open $manifest
    let name = $old.InternalName
    let url = if $old.InstalledFromUrl == "OFFICIAL" { $MAIN_REPO_URL } else { $old.InstalledFromUrl }
    let caches = $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join dalamud-restore
    let cache = $caches | path join $"($url | hash md5).json"
    if not ($cache | path exists) or ((date now) - (ls $cache | get 0.modified)) > $INDEX_MAX_AGE {
        mkdir ($cache | path dirname)
        http get --raw --max-time 60sec $url | save --force $"($cache).tmp"
        mv --force $"($cache).tmp" $cache
    }
    let entry = open $cache | where InternalName == $name | get --optional 0
    if $entry == null {
        print $"note: dalamud: ($name) is gone from ($url), skipped; drop its manifest from configs/secrets/state/dalamud/manifests"
        touch ($cache | path dirname | path join $"($name).delisted")
        return
    }
    let testing = $old.Testing and ($entry.TestingAssemblyVersion? | is-not-empty)
    let version = if $testing { $entry.TestingAssemblyVersion } else { $entry.AssemblyVersion }
    let link = if $testing { $entry.DownloadLinkTesting } else { $entry.DownloadLinkInstall }
    # both name a directory below $plugins, and the version comes from the remote index
    if $name !~ '^[A-Za-z0-9._-]+$' or $name in [. ..] or $version !~ '^[0-9]+(\.[0-9]+)*$' {
        error make {msg: $"dalamud: refusing plugin '($name)' version '($version)' from ($url)"}
    }
    let work = mktemp --directory
    try {
        let dir = $work | path join $name $version
        mkdir $dir
        http get --raw --max-time 300sec $link | save ($work | path join plugin.zip)
        ^bsdtar -xf ($work | path join plugin.zip) -C $dir
        let fresh = $entry | items {|k, v| {k: $k, v: $v} } | where k in ($old | columns) and k not-in $KEPT
        $fresh | reduce --fold $old {|f, acc| $acc | upsert $f.k $f.v }
        | merge {AssemblyVersion: $version, ScheduledForDeletion: false}
        | update DalamudApiLevel {|m| try { $m.DalamudApiLevel | into int } catch { $m.DalamudApiLevel } }
        | to json --indent 2 | save --force ($dir | path join $"($name).json")
        mkdir $plugins
        mv ($work | path join $name) ($plugins | path join $name)
    } catch {|e|
        rm --recursive --force $work
        error make {msg: $e.msg}
    }
    rm --recursive $work
}
