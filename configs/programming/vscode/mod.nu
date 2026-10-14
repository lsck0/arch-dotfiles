use module.nu *

export const meta = {packages: {pacman: [vscodium-bin]}}

const USER_DIR = ".config/VSCodium/User"

# the theme verb and link render the same file, so neither sees the other's write as drift
def settings [] {
    let p = palette-load
    let base = open settings.json
    let text = if $p == null { $base } else {
        # the base theme carries every token not overridden here, so it must match the luminance
        $base | merge {
            "workbench.colorTheme": (if $p.light == "1" { "Default Light Modern" } else { "Default Dark Modern" })
            "workbench.colorCustomizations": {
                "editor.background": $p.bg_conditioned
                "editor.foreground": $p.fg
                "sideBar.background": $p.c0
                "activityBar.background": $p.c0
                "statusBar.background": $p.c0
                "titleBar.activeBackground": $p.c0
                "tab.activeBackground": $p.bg_conditioned
                "tab.inactiveBackground": $p.c0
                "focusBorder": $p.c4
                "terminal.background": $p.bg_conditioned
                "terminal.foreground": $p.fg
            }
        }
    }
    file-text ($nu.home-dir | path join $USER_DIR settings.json) $"($text | to json --indent 2)\n"
}

export def link [cfg: record] {
    let bin = [codium code] | where {|b| which $b | is-not-empty } | get --optional 0
    if $bin == null { return [] }
    let installed = glob ($nu.home-dir | path join .vscode-oss extensions "vscodevim.vim-*") | is-not-empty
    [
        (files-into ($nu.home-dir | path join $USER_DIR) keybindings.json)
        (settings)
        (if $installed { [] } else { [(exec vim-mode [$bin --install-extension vscodevim.vim])] })
    ]
}

export def theme [cfg: record, wallpaper: string] {
    settings
}
