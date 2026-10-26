#!/usr/bin/env -S nu --no-config-file
# Re-pins s14-client.nuon after a PD2 patch: md5 from metadata.json checked, sha256 recorded.

const URL = "https://pd2-client-files.projectdiablo2.com"
const OUT = path self | path dirname | path join s14-client.nuon

def main []: nothing -> nothing {
    let work = mktemp --directory
    let files = http get $"($URL)/metadata.json" | get checksum | parse "{md5}  {name}" | sort-by { $in.name | str downcase }
    let rows = $files | each {|f|
        let dest = $work | path join $f.name
        http get --raw $"($URL)/($f.name | url encode)" | save --force $dest
        let md5 = open --raw $dest | hash md5
        if $md5 != $f.md5 { error make {msg: $"($f.name): md5 ($md5), the manifest says ($f.md5)"} }
        {name: $f.name, sha256: (open --raw $dest | hash sha256), md5: $f.md5}
    }
    rm -rf $work
    let body = $rows | each { $"    [($in.name | to json) \"($in.sha256)\" \"($in.md5)\"]" } | str join "\n"
    [
        $"# Season 14 Alliance client files from ($URL)/, pinned by sha256; md5 is the"
        "# official metadata.json's. Regenerate with pd2-pin.nu when PD2 patches the client."
        "["
        "    [name sha256 md5];"
        $body
        "]"
    ] | str join "\n" | $"($in)\n" | save --force $OUT
    print $"($rows | length) files pinned in ($OUT)"
}
