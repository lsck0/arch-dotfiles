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

export def link [cfg: record] {
    if (which zotero | is-empty) { return [] }
    let home = $nu.home-dir | path join $ZOTERO_HOME
    let ini = $home | path join profiles.ini
    let profiles = if ($ini | path exists) {
        open --raw $ini | lines | parse "Path={path}" | get path | each {|p| $home | path join $p }
        | where ($it | path exists)
    } else { [] }
    [
        # no profile until a first run; the timeout ends the headless one on purpose, the profile is the result
        (exec zotero-profile [sh -c 'timeout 20 zotero --headless > /dev/null 2>&1; true'] --creates $ini)
        # the local api on 127.0.0.1:23119, the only way the mcp reaches zotero: no cloud key
        ($profiles | each {|dir| file-copy user.js ($dir | path join user.js) })
        (json-merge ($nu.home-dir | path join .claude.json) [(json-set [mcpServers zotero-mcp] $MCP)])
    ]
}
