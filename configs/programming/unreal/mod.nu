use module.nu *
use hook/unreal-install.nu [zip-newest]

export const meta = {
    packages: {pacman: [libnotify shared-mime-info unzip]}
    inputs: [~/sync/vendor ~/.local/share/unreal-engine/.installed-from]
}

const HOOK = "hook/unreal-install.nu"
# the editor's MCP server, on unreal-editor.nu's MCP_PORT
const MCP_ADDRESS = "127.0.0.1:8766"
const MCP = {type: http, url: $"http://($MCP_ADDRESS)/mcp", gate: {probe: $MCP_ADDRESS, app: "the Unreal editor"}}

export def link [cfg: record] {
    if $env.FORM_FACTOR? != "desktop" { return [] }
    let mime = xdg data mime
    let stamp = xdg data unreal-engine .installed-from
    let installed = $stamp | path exists
    let zip = zip-newest
    let desktop = xdg data applications unreal-engine.desktop
    let current = $installed and ($desktop | path exists) and (open --raw $stamp | str trim) == ($zip | default "" | path basename)
    [
        (link-commands unreal-editor.nu unreal-install-plugins.nu)
        (file-copy uproject.xml ($mime | path join packages uproject.xml) --then [update-mime-database $mime])
        (mcp-servers {unreal-mcp: (if $installed { $MCP })})
        (exec unreal-install [($env.PWD | path join $HOOK)] --done=($zip == null or $current) --timeout 60min)
        (if not $installed { user-hook unreal-install $HOOK --watch ["%h/sync/vendor"] })
    ]
}
