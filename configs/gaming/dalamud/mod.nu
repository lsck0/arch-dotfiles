use module.nu *

export const meta = {deps: [gaming/ffxiv], backup: {secrets: true}}

const BACKUP_EXCLUDES = [vnavmesh/meshcache/ BossMod/replays/ Questionable/PathData/ '*.bak']

def paths []: nothing -> record {
    let xl = $nu.home-dir | path join .xlcore
    {
        xl: $xl, config: ($xl | path join dalamudConfig.json), plugins: ($xl | path join installedPlugins)
        saved: ($env.DOTFILES | path join secrets dalamud)
    }
}

# seeded once: dalamud rewrites these files in place
export def link [cfg: record] {
    let p = paths
    let unlocked = secret-is-plaintext ($p.saved | path join dalamudConfig.json)
    if (which xivlauncher-core | is-empty) or not $unlocked { return [] }
    let delisted = $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join dalamud-restore
    let manifests = glob ($p.saved | path join manifests *.json)
        | where {|m| not ($delisted | path join $"($m | path parse | get stem).delisted" | path exists) }
    [
        (if ($p.config | path exists) { [] } else { step seed })
        ($manifests | each {|m|
            let name = $m | path parse | get stem
            exec $"dalamud-plugin-($name)" [./plugin-restore.nu $m $p.plugins] --creates ($p.plugins | path join $name)
        })
    ]
}

export def seed []: nothing -> nothing {
    let p = paths
    mkdir ($p.xl | path join pluginConfigs)
    ^cp -n ($p.saved | path join dalamudConfig.json) ($p.saved | path join dalamudUI.ini) $p.xl
    ^cp -rnT ($p.saved | path join pluginConfigs) ($p.xl | path join pluginConfigs)
    touch ($p.xl | path join .dalamud-from-secrets)
}

export def backup [cfg: record]: nothing -> nothing {
    let p = paths
    if not ($p.config | path exists) { error make {msg: $"no ($p.config)"} }
    secret-seed-guard ($p.xl | path join .dalamud-from-secrets) ($p.saved | path join dalamudConfig.json) $p.xl
    mkdir ($p.saved | path join manifests)
    cp --force $p.config ($p.xl | path join dalamudUI.ini) $p.saved
    let excludes = $BACKUP_EXCLUDES | each {|e| [--exclude $e] } | flatten
    ^rsync -a --delete ...$excludes $"($p.xl | path join pluginConfigs)/" ($p.saved | path join pluginConfigs)
    for dir in (glob ($p.plugins | path join *) --no-file) {
        let name = $dir | path basename
        # an uninstall or an interrupted plugin-restore.nu leaves the plugin dir without a version dir
        let newest = glob ($dir | path join *) --no-file | sort --natural | last
        if $newest == null { continue }
        let manifest = $newest | path join $"($name).json"
        if ($manifest | path exists) { cp --force $manifest ($p.saved | path join manifests) }
    }
}
