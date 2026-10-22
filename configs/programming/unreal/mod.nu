use module.nu *

export const meta = {inputs: [~/sync/vendor ~/.local/share/unreal-engine/.installed-from]}

const MCP = {type: http, url: "http://127.0.0.1:8766/mcp"}

def data-dir []: nothing -> path {
    $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share)
}

export def link [cfg: record] {
    if $env.FORM_FACTOR? != "desktop" { return [] }
    let mime = data-dir | path join mime
    let stamp = data-dir | path join unreal-engine .installed-from
    let installed = $stamp | path exists
    let zip = glob ($nu.home-dir | path join sync vendor Linux_Unreal_Engine_*.zip) | sort --natural | last
    let desktop = data-dir | path join applications unreal-engine.desktop
    let current = $installed and ($desktop | path exists) and (open --raw $stamp | str trim) == ($zip | default "" | path basename)
    [
        (link-commands unreal-editor.nu unreal-install-plugins.nu)
        (file-copy uproject.xml ($mime | path join packages uproject.xml) --then [update-mime-database $mime])
        (json-merge ($nu.home-dir | path join .claude.json)
            [(if $installed { json-set [mcpServers unreal-mcp] $MCP } else { json-delete [mcpServers unreal-mcp] })])
        (if $zip == null or $current { [] } else { exec unreal-install [($env.PWD | path join hook unreal-install.nu)] })
        (if $installed { [] } else { user-hook unreal-install hook/unreal-install.nu --watch ["%h/sync/vendor"] })
    ]
}
