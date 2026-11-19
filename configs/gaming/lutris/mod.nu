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
        scope: user
    }
}

const DPI_BASE = 96

# null outside the session (no monitor answers): wine.yml keeps its last dpi
export def detect [cfg: record]: nothing -> record {
    let monitor = monitors-live | sort-by focused --reverse | get --optional 0
    if $monitor == null { return {dpi: null} }
    {dpi: ($DPI_BASE * $monitor.scale | math round | into int)}
}

# Lutris writes both LogPixels keys from a game's own wine options; battle.net's cef renders blank when they differ.
export def link [cfg: record] {
    if (which lutris | is-empty) or $cfg.dpi == null { return [] }
    let config = xdg config lutris
    let dir = if ($config | path exists) { $config } else { xdg data lutris }
    let file = $dir | path join runners wine.yml
    let want = wine-keys $cfg.dpi
    let current = if ($file | path exists) { open $file | get --optional wine | default {} } else { {} }
    let set = $want | columns | all {|k| ($current | get --optional $k) == ($want | get $k) }
    step wine-dpi $file ($cfg.dpi | into string) --done=$set
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
