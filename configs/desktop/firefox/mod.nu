use module.nu *
use ../../core/wallust/palette.nu [RADIUS_PX OPACITY_BAR]

export const meta = {
    packages: {pacman: [espeak-ng firefox python-pywalfox speech-dispatcher]}
    inputs: ["~/.config/mozilla/firefox/profiles.ini"]
    backup: {secrets: true}
}

const HOME_DIR = ".config/mozilla/firefox"
const FIREFOX_DIR = "/usr/lib/firefox"
const POLICIES = "/etc/firefox/policies/policies.json"
const PYWALFOX_HOST = ".mozilla/native-messaging-hosts/pywalfox.json"
# the run is ended on purpose; profiles.ini is the real result
const HEADLESS_TIMEOUT = "20"
const SEARCH_OFF_HOMELAB = {
    Add: [{Name: DuckDuckGo, URLTemplate: "https://duckduckgo.com/?q={searchTerms}", Method: GET, Alias: ddg}]
    Default: DuckDuckGo
}
# NoScript has no managed storage; its allowed sites say where a person browses, so they stay in secrets
const NOSCRIPT_ID = "{73a6fe31-595d-460b-a920-fcc0f8843232}"
const NOSCRIPT_FILE = "secrets/firefox/noscript.json"
const SYNC_DB = "storage-sync-v2.sqlite"
# NoScript's MAX_ITEM_SIZE: a longer value is stored as "[CHUNKED]" plus <key>/CHUNKS and <key>/<n> pieces
const NOSCRIPT_CHUNK = 4096
const NOSCRIPT_SELECT = "select data from storage_sync_data where ext_id = '@ID@'"
const NOSCRIPT_UPSERT = "insert into storage_sync_data (ext_id, data) values ('@ID@', cast(readfile('@FILE@') as text))
    on conflict(ext_id) do update set data = excluded.data, sync_change_counter = sync_change_counter + 1"
const SQLITE_TIMEOUT = ".timeout 5000"
# in a profile that holds the saved sites, so a backup may drop the ones a person removed since
const NOSCRIPT_SEEDED = ".noscript-from-secrets"

def profiles [ini: path]: nothing -> list<path> {
    open --raw $ini | lines | parse "Path={path}" | get path | each {|p| $ini | path dirname | path join $p } | where ($it | path exists)
}

def profile-default [ini: path]: nothing -> any {
    let path = open --raw $ini | split row "\n[" | where ($it | str starts-with "Install") | get --optional 0
        | default "" | lines | parse "Default={path}" | get --optional 0.path
    if $path == null { null } else { $ini | path dirname | path join $path }
}

# a crash or a killed session leaves the lock link behind, so only a live firefox pid counts
def profile-running [dir: path]: nothing -> bool {
    let lock = $dir | path join lock
    if ($lock | path type) != symlink { return false }
    let pid = ^readlink $lock | str trim | parse --regex '\+(?<pid>\d+)$' | get --optional 0.pid
    let comm = $"/proc/($pid)/comm"
    $pid != null and ($comm | path exists) and (open --raw $comm | str trim | str starts-with firefox)
}

def noscript-decode [row: record]: nothing -> record {
    $row | columns | where $it !~ '/' | reduce --fold {} {|key, acc|
        let value = $row | get $key
        $acc | insert $key (if $value != "[CHUNKED]" { $value } else {
            0..<($row | get $"($key)/CHUNKS" | into int) | each {|n| $row | get $"($key)/($n)" } | str join | from json
        })
    }
}

def noscript-encode [values: record]: nothing -> record {
    $values | columns | reduce --fold {} {|key, acc|
        let value = $values | get $key
        let text = $value | to json --raw
        let length = $text | str length --grapheme-clusters
        if $length <= $NOSCRIPT_CHUNK { return ($acc | insert $key $value) }
        let count = $length / $NOSCRIPT_CHUNK | math ceil
        0..<$count | reduce --fold ($acc | insert $key "[CHUNKED]" | insert $"($key)/CHUNKS" $count) {|n, chunks|
            let piece = $text | str substring --grapheme-clusters ($n * $NOSCRIPT_CHUNK)..<(($n + 1) * $NOSCRIPT_CHUNK)
            $chunks | insert $"($key)/($n)" $piece
        }
    }
}

def noscript-load [db: path]: nothing -> record {
    let out = ^sqlite3 -readonly -cmd $SQLITE_TIMEOUT $db ($NOSCRIPT_SELECT | str replace @ID@ $NOSCRIPT_ID) | complete
    if $out.exit_code != 0 { error make {msg: $"($db): ($out.stderr | str trim)"} }
    if ($out.stdout | str trim | is-empty) { {} } else { noscript-decode ($out.stdout | from json) }
}

def noscript-merge [live: record, saved: record]: nothing -> record {
    if $live.policy? == null { return ($live | merge $saved) }
    let sites = $live.policy.sites
    let from = $saved.policy.sites
    let known = $sites.trusted ++ $sites.untrusted ++ ($sites.custom | columns)
    let custom = $from.custom | columns | where $it not-in $known | reduce --fold $sites.custom {|site, acc|
        $acc | insert $site ($from.custom | get $site)
    }
    $live | upsert policy.sites {
        trusted: ($sites.trusted ++ ($from.trusted | where $it not-in $known))
        untrusted: ($sites.untrusted ++ ($from.untrusted | where $it not-in $known))
        custom: $custom
    }
}

def noscript-file []: nothing -> path {
    $env.DOTFILES | path join $NOSCRIPT_FILE
}

# only into a closed profile: firefox holds the database and would write its copy back over this one
def noscript-pending []: nothing -> list<path> {
    let ini = $nu.home-dir | path join $HOME_DIR profiles.ini
    if not ($ini | path exists) or not (secret-is-plaintext (noscript-file)) { return [] }
    let saved = open (noscript-file)
    profiles $ini | where {|dir|
        let db = $dir | path join $SYNC_DB
        if not ($db | path exists) or (profile-running $dir) { return false }
        let live = try { noscript-load $db } catch {|e| log-warn $e.msg; null }
        if $live == null { return false }
        (noscript-merge $live $saved) != $live
    }
}

def chrome-style []: nothing -> string {
    $":root {\n    --rtk-radius: ($RADIUS_PX)px;\n    --appshell-opacity: ($OPACITY_BAR * 100 | math round)%;\n}\n"
}

export def link [cfg: record] {
    let root = $nu.home-dir | path join $HOME_DIR
    let ini = $root | path join profiles.ini
    if not ($ini | path exists) {
        return [(step profile-create)]
    }
    let pywalfox = if (which pywalfox | is-empty) { [] } else {
        [(exec pywalfox-host [pywalfox install] --creates ($nu.home-dir | path join $PYWALFOX_HOST))]
    }
    let speech = if (which speech-dispatcher | is-empty) { [] } else { [(unit-enable speech-dispatcher.socket --now)] }
    let noscript = if (noscript-pending | is-empty) { [] } else { [(step noscript-restore)] }
    # pywalfox looks in ~/.config/firefox
    [(file-link $root ($nu.home-dir | path join .config firefox))]
    | append (profiles $ini | each {|dir|
        [
            # a link: toggle-font rewrites the repo file
            (file-link userChrome.css ($dir | path join chrome userChrome.css))
            (file-text ($dir | path join chrome dotfiles-style.css) (chrome-style) --generated)
            (file-render user.js ($dir | path join user.js) {HOME: $nu.home-dir})
        ]
    } | flatten)
    | append $pywalfox
    | append $speech
    | append $noscript
    | append (user-hook firefox-profiles hook/profile-link.nu --watch [$"%h/($HOME_DIR)/profiles.ini"])
}

export def profile-create [] {
    ^timeout $HEADLESS_TIMEOUT firefox --headless about:blank | complete | ignore
}

export def noscript-restore []: nothing -> nothing {
    let pending = noscript-pending
    if ($pending | is-empty) { return }
    let saved = open (noscript-file)
    for dir in $pending {
        let db = $dir | path join $SYNC_DB
        let file = mktemp --tmpdir noscript.XXXXXX
        noscript-encode (noscript-merge (noscript-load $db) $saved) | to json --raw | save --force $file
        let sql = $NOSCRIPT_UPSERT | str replace @ID@ $NOSCRIPT_ID | str replace @FILE@ $file
        let out = ^sqlite3 -cmd $SQLITE_TIMEOUT $db $sql | complete
        rm $file
        if $out.exit_code != 0 { error make {msg: $"($db): ($out.stderr | str trim)"} }
        touch ($dir | path join $NOSCRIPT_SEEDED)
    }
}

export def backup [cfg: record]: nothing -> nothing {
    let ini = $nu.home-dir | path join $HOME_DIR profiles.ini
    if not ($ini | path exists) { return }
    let dir = profile-default $ini
    if $dir == null or not ($dir | path join $SYNC_DB | path exists) { return }
    let live = noscript-load ($dir | path join $SYNC_DB)
    if $live.policy? == null { return }
    # a profile firefox held open at every link never took the saved sites in; exporting it would drop them
    let seeded = $dir | path join $NOSCRIPT_SEEDED
    if (noscript-file | path exists) and not ($seeded | path exists) {
        if (noscript-merge $live (open (noscript-file))) != $live {
            error make {msg: $"($dir) lacks the saved NoScript sites: close firefox, then dot module restore desktop/firefox"}
        }
        touch $seeded
    }
    mkdir (noscript-file | path dirname)
    $live | upsert policy.sites.trusted { sort } | upsert policy.sites.untrusted { sort } | to json --indent 4
    | $"($in)\n" | save --force (noscript-file)
}

export def restore [cfg: record] {
    noscript-restore
}

export def theme [cfg: record, wallpaper: string] {
    if (which pywalfox | is-empty) { return [] }
    exec pywalfox-update [pywalfox update]
}

# the new tab url is settable only from autoconfig in the install dir; mozilla.cfg reads each user's home at runtime
export def system [cfg: record] {
    let policies = if (platform-has homelab) {
        file-copy policies.json $POLICIES
    } else {
        file-text $POLICIES $"(open policies.json | upsert policies.SearchEngines $SEARCH_OFF_HOMELAB | to json --indent 2)\n"
    }
    let autoconfig = if ($FIREFOX_DIR | path exists) {
        [
            (file-copy autoconfig.js ($FIREFOX_DIR | path join defaults pref autoconfig.js))
            (file-copy mozilla.cfg ($FIREFOX_DIR | path join mozilla.cfg))
        ]
    } else { [] }
    [$policies] | append $autoconfig
}
