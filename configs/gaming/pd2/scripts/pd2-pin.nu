#!/usr/bin/env -S nu --no-config-file
# Re-pins s14-client.nuon after a PD2 patch: md5 from metadata.json checked, sha256 recorded.

use ../../../../scripts/lib/log.nu [log-note log-warn]

export const S14_URL = "https://pd2-client-files.projectdiablo2.com"
const OUT = path self ../config/s14-client.nuon

# The client's files and their md5s as the official metadata.json lists them now.
def metadata-load []: nothing -> table<md5: string, name: string> {
    http get $"($S14_URL)/metadata.json" | get checksum | parse "{md5}  {name}"
}

# The files whose md5 in metadata.json is no longer the pinned one, added and dropped files included: a patch day.
export def s14-drifted [pinned: table]: nothing -> list<string> {
    let live = metadata-load
    let changed = $live | where {|f| ($pinned | where name == $f.name | get --optional 0.md5) != $f.md5 } | get name
    $changed ++ ($pinned | where name not-in $live.name | get name)
}

# gaming/pd2's update verb. PD2 patches the S14 client in place, after which the pinned fetches fail: warns once
# metadata.json's md5s left the pins, so the re-pin comes before the next apply instead of after a failed one.
export def update [cfg: record]: nothing -> nothing {
    # an unreachable client host says nothing about a patch, so it is only noted
    let drifted = try { s14-drifted (open $OUT) } catch {|e| log-note $"pd2: S14 patch check skipped: ($e.msg)"; return }
    if ($drifted | is-not-empty) {
        log-warn $"pd2: PD2 patched the S14 client \(($drifted | str join ', ')\); run configs/gaming/pd2/scripts/pd2-pin.nu"
    }
}

def main []: nothing -> nothing {
    let work = mktemp --directory
    let rows = try {
        let files = metadata-load | sort-by { $in.name | str lowercase }
        $files | each {|f|
            let dest = $work | path join $f.name
            http get --raw $"($S14_URL)/($f.name | url encode)" | save --force $dest
            let md5 = open --raw $dest | hash md5
            if $md5 != $f.md5 { error make {msg: $"($f.name): md5 ($md5), the manifest says ($f.md5)"} }
            {name: $f.name, sha256: (open --raw $dest | hash sha256), md5: $f.md5}
        }
    } catch {|e| rm -rf $work; error make $e }
    rm -rf $work
    let body = $rows | each { $"    [($in.name | to json) \"($in.sha256)\" \"($in.md5)\"]" } | str join "\n"
    [
        $"# Season 14 Alliance client files from ($S14_URL)/, pinned by sha256; md5 is the"
        "# official metadata.json's. Regenerate with pd2-pin.nu when PD2 patches the client."
        "["
        "    [name sha256 md5];"
        $body
        "]"
    ] | to text | save --force $OUT
    print $"($rows | length) files pinned in ($OUT)"
}
