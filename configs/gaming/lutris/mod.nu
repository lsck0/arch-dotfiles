use module.nu *

export const meta = {packages: {pacman: [innoextract lutris python-protobuf umu-launcher]}}

export const options = {
    dpi: {
        type: int?
        default: null
        doc: "Logical dpi wine apps draw at under xwayland (LogPixels), 96 times the main monitor's scale"
        label: "Wine dpi"
        min: 96
        max: 480
    }
}

const DPI_BASE = 96

# hyprland's focused monitor; outside a session the form factor's usual panel (4k at 1.666667 on a desktop)
export def detect [cfg: record]: nothing -> record {
    let scale = try { ^hyprctl -j monitors | from json | sort-by focused --reverse | first | get scale } catch {
        if $env.FORM_FACTOR? == "laptop" { 1 } else { 1.666667 }
    }
    {dpi: ($DPI_BASE * $scale | math round | into int)}
}

# lutris rewrites runners/wine.yml from its preferences dialog, so the two keys are merged in on each run; a game's own
# wine options still win, and lutris writes both LogPixels keys from them (battle.net's cef renders blank when they
# differ)
export def link [cfg: record] {
    if (which lutris | is-empty) { return [] }
    # lutris reads ~/.config/lutris only when it exists
    let config = $nu.home-dir | path join .config lutris
    let dir = if ($config | path exists) { $config } else { $nu.home-dir | path join .local share lutris }
    let file = $dir | path join runners wine.yml
    let want = wine-keys $cfg.dpi
    let current = if ($file | path exists) { open $file | get --optional wine | default {} } else { {} }
    if ($want | columns | all {|k| ($current | get --optional $k) == ($want | get $k) }) { return [] }
    step wine-dpi $file ($cfg.dpi | into string)
}

def wine-keys [dpi: int]: nothing -> record {
    {Dpi: ($dpi != $DPI_BASE), ExplicitDpi: ($dpi | into string)}
}

export def wine-dpi [file: path, dpi: string]: nothing -> nothing {
    let config = if ($file | path exists) { open $file | default {} } else { {} }
    mkdir ($file | path dirname)
    $config | upsert wine {|c| $c.wine? | default {} | merge (wine-keys ($dpi | into int)) }
    | to yaml | save --force $file
}
