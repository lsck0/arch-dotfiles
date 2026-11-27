use module.nu *
use ../../core/wallust/scripts/font.nu [font-load]
use scripts/steam-launch-options.nu [LAUNCH_OPTIONS_DEFAULT launch-options-fingerprint steam-open wanted-file]
use scripts/steam-bootstrap.nu [MILLENNIUM_LIB bootstrap-pending]

export const meta = {deps: [gaming/gamemode gaming/mangohud], packages: {pacman: [millennium steam]}}

export const options = {
    launch_options: {
        type: string
        default: $LAUNCH_OPTIONS_DEFAULT
        doc: "Launch options filled into every installed game whose own are empty or ours; empty for none, %command% is the game"
        label: "Game launch options"
        scope: user
    }
    millennium: {
        type: bool
        default: true
        doc: "The Millennium client mod with the themed cyberpunk skin; off unlinks it for this login, the package stays"
        label: "Millennium skin"
        scope: user
    }
}

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
    # off: the links into millennium go, so this login's steam starts the stock client
    let bootstrap = [nu --no-config-file scripts/steam-bootstrap.nu] ++ (if $cfg.millennium { [] } else { [--no-millennium] })
    [
        (desktop-override steam.desktop {
            $in | str replace --all "/usr/bin/steam" ($env.PWD | path join scripts steam-launch.nu)
        })
        (if $cfg.millennium {
            [
                (files-into $theme ...(glob config/themes/cyberpunk/*))
                # millennium ignores links out of the theme dir, so the palette is a copy; the theme verb refreshes it
                (exec steam-palette [cp $palette $colors] --creates $colors --requires $palette)
                (json-merge (xdg config millennium config.json) [
                    (json-set [themes activeTheme] cyberpunk)
                ])
            ]
        })
        (if $cfg.launch_options != $LAUNCH_OPTIONS_DEFAULT { file-text (wanted-file) $cfg.launch_options })
        (link-commands scripts/steam-launch-options.nu)
        (step launch-options --key (launch-options-fingerprint $cfg.launch_options))
        (if $cfg.millennium and not $linked {
            let installed = "%h/.local/share/Steam/package/steam_client_ubuntu12.installed"
            user-hook steam-bootstrap scripts/steam-bootstrap.nu --no-brake --watch [$installed]
        })
        (exec steam-bootstrap $bootstrap --done=(not (bootstrap-pending --no-millennium=(not $cfg.millennium))))
    ]
}

# font.css is imported after shared.css, whose --cp-font holds until the first theme run; wallust renders the palette
# only into the cache, so a login without the skin gets no Steam tree
export def theme [cfg: record, wallpaper: string] {
    if not $cfg.millennium { return [] }
    let family = font-load | get family
    let css = $":root {\n    --cp-font: \"($family)\", \"JetBrainsMono Nerd Font\", sans-serif;\n}\n"
    let palette = xdg cache wal colors-steam.css
    [
        (file-text (theme-dir | path join font.css) $css --generated)
        (exec steam-palette [cp $palette (theme-dir | path join colors.css)] --requires $palette)
    ]
}
