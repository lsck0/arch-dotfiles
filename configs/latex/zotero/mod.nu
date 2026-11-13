use module.nu *

export const meta = {packages: {pacman: [zotero-bin uv]}}

const ZOTERO_HOME = ".zotero/zotero"
# MCP_FROZEN cuts off its deps (mcp-uvx); bump both together
const MCP_VERSION = "0.14.1"
const MCP_FROZEN = "2026-10-08"
const BBT_VERSION = "9.0.71"
const BBT_URL = $"https://github.com/retorquere/zotero-better-bibtex/releases/download/v($BBT_VERSION)/zotero-better-bibtex-($BBT_VERSION).xpi"
const BBT_SHA256 = "bf61a1690dc8a2b7ab09be9de2c89986f4fb6d495c82407d89b102b26fbaa9d5"
const BBT_ID = "better-bibtex@iris-advies.com"
const BBT_TRANSLATOR_BIBTEX = "ca65189f-8815-4afe-8c8b-8c7c15f0edca"
const ZOTERO_USER_LIBRARY_ID = 1
const ZOTERO_SERVER = "http://127.0.0.1:23119"
const BBT_READY = $"($ZOTERO_SERVER)/better-bibtex/cayw?probe=true"
const BBT_EXPORT = $"($ZOTERO_SERVER)/better-bibtex/export/library?/($ZOTERO_USER_LIBRARY_ID)/library.bibtex"
const PROFILE_TIMEOUT_S = 20
const EXPORT_TIMEOUT = 120sec
const READY_TIMEOUT = 90sec
const READY_POLL_INTERVAL = 1sec
const READY_PROBE_TIMEOUT = 2sec

# Better BibTeX's pref key for an auto-export to file: encodeURIComponent, then .!'()* as lowercase %xx.
def autoexport-key [file: path]: nothing -> string {
    $file | url encode --all
    | str replace --all "%2D" "-" | str replace --all "%5F" "_" | str replace --all "%7E" "~"
    | str replace --all "%2E" "%2e" | str replace --all "%2A" "%2a"
}

def autoexport-job [file: path]: nothing -> string {
    {
        enabled: true, type: library, id: $ZOTERO_USER_LIBRARY_ID, path: $file, status: done, recursive: false,
        error: "", translatorID: $BBT_TRANSLATOR_BIBTEX, exportNotes: false, useJournalAbbreviation: false
    } | to json --raw | to json --raw
}

export def link [cfg: record] {
    if (which zotero | is-empty) { return [] }
    let home = $nu.home-dir | path join $ZOTERO_HOME
    let ini = $home | path join profiles.ini
    let profiles = if ($ini | path exists) {
        open --raw $ini | lines | parse "Path={path}" | get path | each {|p| $home | path join $p }
        | where ($it | path exists)
    } else { [] }
    let bib = xdg data zotero library.bib
    let xpi = $"extensions/($BBT_ID).xpi"
    let prefs = {EXPORT_KEY: (autoexport-key $bib), EXPORT_JOB: (autoexport-job $bib)}
    [
        # the timeout ends the headless first run on purpose: the profile it creates is the result
        (exec zotero-profile [sh -c $"timeout ($PROFILE_TIMEOUT_S) zotero --headless > /dev/null 2>&1; true"] --creates $ini)
        ($profiles | each {|dir|
            [(file-render user.js ($dir | path join user.js) $prefs) (fetch-file $BBT_URL $BBT_SHA256 ($dir | path join $xpi))]
        })
        # the auto-export runs only on a library change, so an unchanged library never gets its file
        # better bibtex answers the export; its download may still be pending (offline), then the export waits too
        (if ($profiles | is-not-empty) and not ($bib | path exists) {
            step library-export $bib --requires ($profiles | first | path join $xpi)
        })
        (mcp-uvx zotero-mcp $"zotero-mcp-server==($MCP_VERSION)" $MCP_FROZEN [zotero-mcp serve] zotero_mcp.server
            --env-vars {ZOTERO_LOCAL: "true", ZOTERO_MCP_SCHEMA_REFRESH: "0", ZOTERO_NO_CLAUDE: "true"})
    ]
}

def bbt-ready []: nothing -> bool {
    (try { http get --max-time $READY_PROBE_TIMEOUT $BBT_READY } catch { "" }) == "ready"
}

# Exports the library to <bib> from a running zotero, else from a headless one started for it and stopped after.
export def library-export [bib: path]: nothing -> nothing {
    let started = if (bbt-ready) { null } else {
        let seconds = $EXPORT_TIMEOUT / 1sec | into int
        # timeout puts zotero in its own process group and passes a TERM on to all of it, the wrapper script included
        ^sh -c $"timeout ($seconds) zotero --headless >/dev/null 2>&1 & echo $!" | str trim | into int
    }
    # the ready deadline stays below EXPORT_TIMEOUT, so the export gets the rest before timeout ends zotero
    let deadline = (date now) + $READY_TIMEOUT
    mut ready = $started == null
    while not $ready and (date now) < $deadline {
        sleep $READY_POLL_INTERVAL
        $ready = bbt-ready
    }
    let export = if $ready {
        mkdir ($bib | path dirname)
        try { http get --raw $BBT_EXPORT | save --force $bib; null } catch {|e| $e.msg }
    } else { "zotero's better bibtex did not answer; dot apply latex/zotero again once zotero starts" }
    if $started != null { ^kill $started }
    if $export != null { error make {msg: $export} }
}
