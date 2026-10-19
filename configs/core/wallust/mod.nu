use module.nu *
use palette.nu [style-json]

export const meta = {
    packages: {pacman: [imagemagick wallust-git]}
}

const CONFIG_DIR = ".config/wallust"
const STAND_IN = "void"
const STYLE_JSON = ".config/dotfiles/style.json"

export def link [cfg: record] {
    let dir = $nu.home-dir | path join $CONFIG_DIR
    let templates = glob templates/**/* --no-dir | each { path relative-to $env.PWD }
    [
        (file-copy wallust.toml ($dir | path join wallust.toml))
        ($templates | each {|t| file-copy $t ($dir | path join $t) })
        (files-into ($dir | path join colorschemes) ...(glob ../../../themes/*.json))
        (file-text ($nu.home-dir | path join $STYLE_JSON) (style-json) --generated)
        # a fresh home has no palette until the first theme switch, but theme verbs of later modules read colors.json now
        (if (which wallust | is-empty) { [] } else {
            exec palette-stand-in [wallust cs -q -s $STAND_IN] --creates ($nu.home-dir | path join .cache wal colors.json)
        })
    ]
}
