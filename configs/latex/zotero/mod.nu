use module.nu *

export const meta = {packages: {pacman: [zotero-bin]}}

const ZOTERO_HOME = ".zotero/zotero"
# the aur zotero-mcp-server needs python packages the aur lacks, so uvx runs the pinned pypi release
const MCP = {
    type: stdio
    command: uvx
    args: [--from zotero-mcp-server==0.14.1 zotero-mcp serve]
    env: {ZOTERO_LOCAL: "true", ZOTERO_MCP_SCHEMA_REFRESH: "0", ZOTERO_NO_CLAUDE: "true"}
}
const BBT_VERSION = "9.0.71"
const BBT_URL = $"https://github.com/retorquere/zotero-better-bibtex/releases/download/v($BBT_VERSION)/zotero-better-bibtex-($BBT_VERSION).xpi"
const BBT_SHA256 = "bf61a1690dc8a2b7ab09be9de2c89986f4fb6d495c82407d89b102b26fbaa9d5"
const BBT_ID = "better-bibtex@iris-advies.com"
const BBT_TRANSLATOR_BIBTEX = "ca65189f-8815-4afe-8c8b-8c7c15f0edca"
const ZOTERO_USER_LIBRARY_ID = 1

def library-bib-path []: nothing -> path {
    $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join zotero library.bib
}

# better bibtex's pref key for an auto-export: encodeURIComponent, then .!'()* as lowercase %xx
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
    let bib = library-bib-path
    let prefs = {EXPORT_KEY: (autoexport-key $bib), EXPORT_JOB: (autoexport-job $bib)}
    [
        # no profile until a first run; the timeout ends the headless one on purpose, the profile is the result
        (exec zotero-profile [sh -c 'timeout 20 zotero --headless > /dev/null 2>&1; true'] --creates $ini)
        ($profiles | each {|dir| file-render user.js ($dir | path join user.js) $prefs })
        ($profiles | each {|dir| fetch-file $BBT_URL $BBT_SHA256 ($dir | path join extensions $"($BBT_ID).xpi") } | flatten)
        (json-merge ($nu.home-dir | path join .claude.json) [(json-set [mcpServers zotero-mcp] $MCP)])
    ]
}
