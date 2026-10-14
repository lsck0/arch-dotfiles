use module.nu *
use written.nu [preserve-aside]

export const meta = {packages: {pacman: [gimp]}}

# PhotoGIMP: photoshop shortcuts, tool layout and docks over gimp's config. the release has no checksum and a tag can be
# re-uploaded, so the archive is pinned by content; bump both together
const PHOTOGIMP_VERSION = "3.1"
const PHOTOGIMP_SHA256 = "bf0e1279870d40152beb3e702cf3e4e01a6892031a1ace5bc4a9b858894b584e"
const PHOTOGIMP_URL = $"https://github.com/Diolinux/PhotoGIMP/releases/download/($PHOTOGIMP_VERSION)/PhotoGIMP-linux.zip"
# gimp 3.2 renamed vectors to paths and rejects a whole toolrc over one unknown tool name
const RENAMES = {gimp-vector-tool: gimp-path-tool, tools-vector: tools-path, gimp-vectors-list: gimp-path-list}
const RENAMED_FILES = [toolrc shortcutsrc sessionrc]

def unpacked []: nothing -> path {
    $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join photogimp $PHOTOGIMP_VERSION
}

def stale [dir: path]: nothing -> bool {
    $RENAMED_FILES | each {|f| $dir | path join $f } | where ($it | path exists)
    | any {|f| let text = open --raw $f; $RENAMES | columns | any {|old| $text | str contains $'"($old)"' } }
}

# gimp rewrites these files itself, so they are seeded once per release, then left to it; an installed 3.2 reads its
# own dir and migrates 3.0's only while its own is missing, so the release's 3.0 tree goes into the installed version
export def link [cfg: record] {
    if (which gimp | is-empty) { return [] }
    let version = ^gimp --version | parse --regex '(?<v>\d+\.\d+)' | get 0.v
    let config = $nu.home-dir | path join .config GIMP $version
    if ($config | path join $".photogimp-($PHOTOGIMP_VERSION)" | path exists) {
        return (if $version != "3.0" and (stale $config) { step migrate $config } else { [] })
    }
    [
        (fetch-file $PHOTOGIMP_URL $PHOTOGIMP_SHA256 (unpacked) --extract .)
        (step seed $config $version)
    ]
}

export def migrate [dir: path]: nothing -> nothing {
    for file in ($RENAMED_FILES | each {|f| $dir | path join $f } | where ($it | path exists)) {
        $RENAMES | items {|old, new| {old: $'"($old)"', new: $'"($new)"'} }
        | reduce --fold (open --raw $file) {|r, text| $text | str replace --all $r.old $r.new } | save --force $file
    }
}

# only the gimp config: the release's .desktop runs the flatpak. a file of gimp's own it replaces is preserved first
export def seed [config: path, version: string]: nothing -> nothing {
    let src = unpacked | path join PhotoGIMP-linux .config GIMP "3.0"
    if $version != "3.0" { migrate $src }
    for file in (glob ($src | path join **/*) --no-dir) {
        let dest = $config | path join ($file | path relative-to $src)
        if ($dest | path exists) and (open --raw $dest | hash sha256) != (open --raw $file | hash sha256) {
            preserve-aside $dest | ignore
        }
        mkdir ($dest | path dirname)
        cp --force $file $dest
    }
    touch ($config | path join $".photogimp-($PHOTOGIMP_VERSION)")
}
