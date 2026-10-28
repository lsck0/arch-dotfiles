use module.nu *
use ../../core/wallust/font.nu [font-load]

export const meta = {packages: {pacman: [vscodium-bin]}}

# Merged, not rendered: VSCodium rewrites settings.json from its settings UI and keeps its own keys there.
def settings [user_dir: path] {
    let p = palette-load
    let theme = if $p == null { {} } else {
        {
            # the base theme carries every token not overridden here, so its luminance must match
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
    let font = font-load
    let typeface = {"editor.fontFamily": $"'($font.mono)', 'monospace'", "editor.fontSize": $font.size}
    let edits = open settings.json | merge $typeface | merge $theme | items {|k, v| json-set [$k] $v }
    json-merge ($user_dir | path join settings.json) $edits
}

def code-bin []: nothing -> any { [codium code] | where {|b| which $b | is-not-empty } | get --optional 0 }

# codium and code read different config roots, so the settings follow the binary that is actually present
def code-user-dir [bin: string]: nothing -> path { xdg config (if $bin == codium { "VSCodium" } else { "Code" }) User }

export def link [cfg: record] {
    let bin = code-bin
    if $bin == null { return [] }
    let user_dir = code-user-dir $bin
    let installed = glob ($nu.home-dir | path join .vscode-oss extensions "vscodevim.vim-*") | is-not-empty
    [
        (files-into $user_dir keybindings.json)
        (settings $user_dir)
        (if $installed { [] } else { [(exec vim-mode [$bin --install-extension vscodevim.vim])] })
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let bin = code-bin
    if $bin == null { return [] }
    settings (code-user-dir $bin)
}
