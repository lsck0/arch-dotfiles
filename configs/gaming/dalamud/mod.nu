use module.nu *

export const meta = {deps: [gaming/ffxiv], backup: {secrets: true}}

const BACKUP_EXCLUDES = [vnavmesh/meshcache/ BossMod/replays/ Questionable/PathData/ '*.bak']

def paths []: nothing -> record {
    let xl = $nu.home-dir | path join .xlcore
    let shared = $env.DOTFILES | path join configs secrets state dalamud
    {
        xl: $xl, config: ($xl | path join dalamudConfig.json), plugins: ($xl | path join installedPlugins)
        manifests: ($shared | path join manifests), saved: (host-file $shared)
        seed: {
            config: (host-seed $shared dalamudConfig.json), ui: (host-seed $shared dalamudUI.ini)
            plugin_configs: (host-seed $shared pluginConfigs)
        }
    }
}

# Seeded once: dalamud rewrites these files in place.
export def link [cfg: record] {
    let p = paths
    let unlocked = secret-is-plaintext $p.seed.config
    if (which xivlauncher-core | is-empty) or not $unlocked { return [] }
    let delisted = xdg cache dalamud-restore
    let manifests = glob ($p.manifests | path join *.json)
        | where {|m| not ($delisted | path join $"($m | path parse | get stem).delisted" | path exists) }
    [
        (if ($p.config | path exists) { [] } else { step seed })
        ($manifests | each {|m|
            let name = $m | path parse | get stem
            exec $"dalamud-plugin-($name)" [./plugin-restore.nu $m $p.plugins] --creates ($p.plugins | path join $name) --network
        })
    ]
}

export def seed []: nothing -> nothing {
    let p = paths
    mkdir ($p.xl | path join pluginConfigs)
    ^cp -n $p.seed.config ($p.xl | path join dalamudConfig.json)
    ^cp -n $p.seed.ui ($p.xl | path join dalamudUI.ini)
    ^cp -rnT $p.seed.plugin_configs ($p.xl | path join pluginConfigs)
    touch ($p.xl | path join .dalamud-from-secrets)
}

export def backup [cfg: record]: nothing -> nothing {
    let p = paths
    if not ($p.config | path exists) { error make {msg: $"no ($p.config)"} }
    secret-seed-guard ($p.xl | path join .dalamud-from-secrets) $p.seed.config $p.xl
    mkdir $p.manifests $p.saved
    cp --force $p.config ($p.xl | path join dalamudUI.ini) $p.saved
    let excludes = $BACKUP_EXCLUDES | each {|e| [--exclude $e] } | flatten
    ^rsync -a --delete ...$excludes $"($p.xl | path join pluginConfigs)/" ($p.saved | path join pluginConfigs)
    for dir in (glob ($p.plugins | path join *) --no-file) {
        let name = $dir | path basename
        let newest = glob ($dir | path join *) --no-file | sort --natural | last
        if $newest == null { continue }
        let manifest = $newest | path join $"($name).json"
        if ($manifest | path exists) { cp --force $manifest $p.manifests }
    }
}
