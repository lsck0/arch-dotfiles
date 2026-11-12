#!/usr/bin/env -S nu --no-config-file
# installed as dalamud's installer would: dalamud never installs a collection's plugins by itself

use ../../../scripts/lib/state.nu [EXIT_PENDING xdg]

const MAIN_REPO_URL = "https://kamori.goats.dev/Plugin/PluginMaster"
const KEPT = [
    Disabled Testing InstalledFromUrl WorkingPluginId IsThirdParty IsHide DownloadLinkInstall DownloadLinkTesting
    DownloadLinkUpdate DownloadCount LastUpdate TestingAssemblyVersion TestingDalamudApiLevel
]
const INDEX_MAX_AGE = 10min

# A plugin left out for good: its repo or its entry is gone.
def delist [cache: path, name: string, why: string]: nothing -> nothing {
    print $"note: dalamud: ($name) ($why), skipped; drop its manifest from configs/secrets/state/dalamud/manifests"
    touch ($cache | path dirname | path join $"($name).delisted")
}

def main [manifest: path, plugins: path]: nothing -> nothing {
    let old = open $manifest
    let name = $old.InternalName
    let url = if $old.InstalledFromUrl == "OFFICIAL" { $MAIN_REPO_URL } else { $old.InstalledFromUrl }
    let cache = xdg cache dalamud-restore $"($url | hash md5).json"
    if not ($cache | path exists) or ((date now) - (ls $cache | get 0.modified)) > $INDEX_MAX_AGE {
        mkdir ($cache | path dirname)
        let got = do { ^curl -fsSL --max-time 60 -o $"($cache).tmp" $url } | complete
        if $got.exit_code != 0 {
            # 4xx: the repo is gone; anything else (timeout, 5xx, no route) is the remote's state for now
            if ($got.stderr =~ 'returned error: 4\d\d') { delist $cache $name $"has no repo at ($url) any more"; return }
            print $"dalamud: ($url) not reachable: ($got.stderr | str trim)"
            exit $EXIT_PENDING
        }
        mv --force $"($cache).tmp" $cache
    }
    let index = try { open $cache } catch { null }
    if ($index | describe) !~ '^(table|list<record)' {
        delist $cache $name $"gets no plugin index from ($url)"
        return
    }
    let entry = $index | where InternalName == $name | get --optional 0
    if $entry == null {
        delist $cache $name $"is gone from ($url)"
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
        error make $e
    }
    rm --recursive $work
}
