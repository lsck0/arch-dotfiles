use module.nu *

export const meta = {packages: {pacman: [millennium steam]}}

const STEAM = ".local/share/Steam"
const MILLENNIUM_LIB = "/usr/lib/millennium"

def theme-dir []: nothing -> path {
    $nu.home-dir | path join $STEAM millennium themes cyberpunk
}

export def link [cfg: record] {
    let steam = $nu.home-dir | path join $STEAM
    let palette = $nu.home-dir | path join .cache wal colors-steam.css
    let colors = theme-dir | path join colors.css
    let xtst = try { ^readlink ($steam | path join ubuntu12_32 libXtst.so.6) | str trim } catch { "" }
    let linked = $xtst | str starts-with $"($MILLENNIUM_LIB)/"
    [
        (desktop-override steam.desktop {
            $in | str replace --all "/usr/bin/steam" ($env.PWD | path join steam-launch.nu)
        })
        (glob themes/cyberpunk/* | each {|f| file-copy $f (theme-dir | path join ($f | path basename)) })
        # millennium ignores links out of the theme dir; a palette rendered before the dir existed only needs copying
        (if ($palette | path exists) and not ($colors | path exists) {
            exec steam-palette [cp $palette $colors] --creates $colors
        } else { [] })
        (json-merge ($nu.home-dir | path join .config millennium config.json) [
            (json-set [themes activeTheme] cyberpunk)
        ])
        (link-commands steam-launch-options.nu)
        (exec steam-launch-options [nu --no-config-file steam-launch-options.nu])
        (if $linked { [] } else {
            let installed = "%h/.local/share/Steam/package/steam_client_ubuntu12.installed"
            user-hook steam-bootstrap hook/steam-bootstrap.nu --no-brake --watch [$installed]
        })
        (exec steam-bootstrap [nu --no-config-file hook/steam-bootstrap.nu])
    ]
}
