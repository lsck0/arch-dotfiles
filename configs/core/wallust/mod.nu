use module.nu *
use palette.nu [style-json]

export const meta = {
    packages: {pacman: [imagemagick wallust-git]}
}

const CONFIG_SUBDIR = "wallust"
const STAND_IN = "void"
const STYLE_JSON = "dotfiles/style.json"

export def link [cfg: record] {
    let dir = xdg config $CONFIG_SUBDIR
    let templates = glob templates/**/* --no-dir | each { path relative-to $env.PWD }
    [
        (file-render wallust.toml ($dir | path join wallust.toml) {CACHE: (xdg cache), DATA: (xdg data)})
        ($templates | each {|t| file-copy $t ($dir | path join $t) })
        (files-into ($dir | path join colorschemes) ...(glob ../../../themes/*.json))
        (file-text (xdg config $STYLE_JSON) (style-json) --generated)
        (unit-file dot-theme.service)
        (unit-file dot-theme.path --enable --now)
        # theme verbs of later modules read colors.json now, before a fresh home's first theme switch
        (if (which wallust | is-empty) { [] } else {
            exec palette-stand-in [wallust cs -q -s ($dir | path join colorschemes $"($STAND_IN).json")] --creates (xdg cache wal colors.json)
        })
    ]
}
