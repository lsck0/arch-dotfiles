use module.nu *
use steam-launch-options.nu [launch-options-fingerprint steam-open]
use hook/steam-bootstrap.nu [bootstrap-pending]

export const meta = {deps: [gaming/gamemode gaming/mangohud], packages: {pacman: [millennium steam]}}

const MILLENNIUM_LIB = "/usr/lib/millennium"

# Pending while steam is open, so the key is recorded only once a fill got through.
export def launch-options []: nothing -> nothing {
    if (steam-open) {
        print "steam is open, it overwrites localconfig.vdf on exit"
        exit $EXIT_PENDING
    }
    ^nu --no-config-file steam-launch-options.nu
}

def theme-dir []: nothing -> path {
    xdg data Steam millennium themes cyberpunk
}

export def link [cfg: record] {
    let steam = xdg data Steam
    let palette = xdg cache wal colors-steam.css
    let colors = theme-dir | path join colors.css
    let xtst = try { ^readlink ($steam | path join ubuntu12_32 libXtst.so.6) | str trim } catch { "" }
    let linked = $xtst | str starts-with $"($MILLENNIUM_LIB)/"
    [
        (desktop-override steam.desktop {
            $in | str replace --all "/usr/bin/steam" ($env.PWD | path join steam-launch.nu)
        })
        (glob themes/cyberpunk/* | each {|f| file-copy $f (theme-dir | path join ($f | path basename)) })
        # millennium ignores links out of the theme dir; a palette rendered before the dir existed only needs copying
        (exec steam-palette [cp $palette $colors] --creates $colors --requires $palette)
        (json-merge (xdg config millennium config.json) [
            (json-set [themes activeTheme] cyberpunk)
        ])
        (link-commands steam-launch-options.nu)
        (step launch-options --key (launch-options-fingerprint))
        (if $linked { [] } else {
            let installed = "%h/.local/share/Steam/package/steam_client_ubuntu12.installed"
            user-hook steam-bootstrap hook/steam-bootstrap.nu --no-brake --watch [$installed]
        })
        (exec steam-bootstrap [nu --no-config-file hook/steam-bootstrap.nu] --done=(not (bootstrap-pending)))
    ]
}
