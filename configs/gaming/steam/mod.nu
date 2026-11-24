use module.nu *
use ../../core/wallust/scripts/font.nu [font-load]
use scripts/steam-launch-options.nu [launch-options-fingerprint steam-open]
use scripts/steam-bootstrap.nu [MILLENNIUM_LIB bootstrap-pending]

export const meta = {deps: [gaming/gamemode gaming/mangohud], packages: {pacman: [millennium steam]}}

# Pending while steam is open, so the key is recorded only once a fill got through.
export def launch-options []: nothing -> nothing {
    if (steam-open) {
        print "steam is open, it overwrites localconfig.vdf on exit"
        exit $EXIT_PENDING
    }
    ^nu --no-config-file scripts/steam-launch-options.nu
}

def theme-dir []: nothing -> path { xdg data Steam millennium themes cyberpunk }

export def link [cfg: record] {
    let steam = xdg data Steam
    let theme = theme-dir
    let palette = xdg cache wal colors-steam.css
    let colors = $theme | path join colors.css
    let xtst = try { ^readlink ($steam | path join steamrt64 libXtst.so.6) | str trim } catch { "" }
    let linked = $xtst | str starts-with $"/run/host($MILLENNIUM_LIB)/"
    [
        (desktop-override steam.desktop {
            $in | str replace --all "/usr/bin/steam" ($env.PWD | path join scripts steam-launch.nu)
        })
        (files-into $theme ...(glob config/themes/cyberpunk/*))
        # millennium ignores links out of the theme dir; a palette rendered before the dir existed only needs copying
        (exec steam-palette [cp $palette $colors] --creates $colors --requires $palette)
        (json-merge (xdg config millennium config.json) [
            (json-set [themes activeTheme] cyberpunk)
        ])
        (link-commands scripts/steam-launch-options.nu)
        (step launch-options --key (launch-options-fingerprint))
        (if not $linked {
            let installed = "%h/.local/share/Steam/package/steam_client_ubuntu12.installed"
            user-hook steam-bootstrap scripts/steam-bootstrap.nu --no-brake --watch [$installed]
        })
        (exec steam-bootstrap [nu --no-config-file scripts/steam-bootstrap.nu] --done=(not (bootstrap-pending)))
    ]
}

# font.css is imported after shared.css, whose --cp-font holds until the first theme run
export def theme [cfg: record, wallpaper: string] {
    let family = font-load | get family
    let css = $":root {\n    --cp-font: \"($family)\", \"JetBrainsMono Nerd Font\", sans-serif;\n}\n"
    file-text (theme-dir | path join font.css) $css --generated
}
