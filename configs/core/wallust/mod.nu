use module.nu *
use scripts/palette.nu [style-json wal-colors-file]

export const meta = {
    deps: [base/essentials core/cli]
    packages: {pacman: [imagemagick wallust-git]}
}

const STAND_IN = "void"
const STYLE_JSON = "dotfiles/style.json"

export def link [cfg: record] {
    let dir = xdg config wallust
    let templates = glob config/templates/**/* --no-dir | each { path relative-to ($env.PWD | path join config) }
    [
        (shell-aliases wallust)
        (file-render config/wallust.toml ($dir | path join wallust.toml) {CACHE: (xdg cache), DATA: (xdg data)})
        ($templates | each {|t| file-copy ("config" | path join $t) ($dir | path join $t) })
        (files-into ($dir | path join colorschemes) ...(glob ../../../themes/*.json))
        (file-text (xdg config $STYLE_JSON) (style-json) --generated)
        (unit-file config/dot-theme.service)
        (unit-file config/dot-theme.path --enable --now)
        # theme verbs of later modules read colors.json now, before a fresh home's first theme switch
        (if (which wallust | is-not-empty) {
            exec palette-stand-in [wallust cs -q -s ($dir | path join colorschemes $"($STAND_IN).json")] --creates (wal-colors-file)
        })
    ]
}
