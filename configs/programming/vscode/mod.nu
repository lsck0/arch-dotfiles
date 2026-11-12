use module.nu *
use ../../core/wallust/font.nu [font-load]
use ../../core/wallust/palette.nu [SHADE_CHROME hex-to-rgb rgb-to-hex shade]

export const meta = {packages: {pacman: [vscodium-bin]}}

# codium and code read different config and extension roots, so the settings follow the binary that is present
const EDITIONS = [[bin config extensions]; [codium VSCodium ".vscode-oss"] [code Code ".vscode"]]

# Merged, not rendered: VSCodium rewrites settings.json from its settings UI and keeps its own keys there.
def settings [user_dir: path]: nothing -> record {
    let p = palette-load
    let theme = if $p == null { {} } else {
        let chrome = $p.bg_conditioned | hex-to-rgb | shade $SHADE_CHROME | rgb-to-hex --prefix "#"
        {
            # the base theme carries every token not overridden here, so its luminance must match
            "workbench.colorTheme": (if $p.light == "1" { "Default Light Modern" } else { "Default Dark Modern" })
            "workbench.colorCustomizations": {
                "editor.background": $p.bg_conditioned
                "editor.foreground": $p.fg
                "sideBar.background": $chrome
                "activityBar.background": $chrome
                "statusBar.background": $chrome
                "titleBar.activeBackground": $chrome
                "tab.activeBackground": $p.bg_conditioned
                "tab.inactiveBackground": $chrome
                "focusBorder": $p.c4
                "terminal.background": $p.bg_conditioned
                "terminal.foreground": $p.fg
            }
        }
    }
    let font = font-load
    let typeface = {"editor.fontFamily": $"'($font.mono)', 'monospace'", "editor.fontSize": $font.size}
    let edits = open settings.json | merge $typeface | merge $theme | items {|k, v| json-set [$k] $v }
    json-merge ($user_dir | path join settings.json) $edits
}

def edition []: nothing -> any { $EDITIONS | where {|e| which $e.bin | is-not-empty } | get --optional 0 }

export def link [cfg: record] {
    let edition = edition
    if $edition == null { return [] }
    let bin = $edition.bin
    let user_dir = xdg config $edition.config User
    let installed = glob ($nu.home-dir | path join $edition.extensions extensions "vscodevim.vim-*") | is-not-empty
    [
        (files-into $user_dir keybindings.json)
        (settings $user_dir)
        (exec vim-mode [$bin --install-extension vscodevim.vim] --done=$installed --undo [$bin --uninstall-extension vscodevim.vim] --network)
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let edition = edition
    if $edition == null { return [] }
    settings (xdg config $edition.config User)
}
