use module.nu *

export const meta = {packages: {pacman: [python]}}

export const options = {
    preset: {
        type: string
        default: default
        choices: [off default reading grayscale]
        doc: "Preset before the toggle first picks one (default: warmer, more contrast; off: the output untouched)"
        label: "Starting preset"
        scope: user
    }
}

const UNIT = "color-grading.service"
const SCRIPT = path self scripts/color-grading.py

export def link [cfg: record] {
    let script_hash = open --raw $SCRIPT | hash sha256
    # the script takes no preset file as default; the toggle owns the file once it exists
    let preset_file = xdg state color-grading preset
    [
        (if $cfg.preset != default {
            # the daemon rereads its state files only on SIGHUP
            (exec color-grading-preset [sh -c 'mkdir -p "${0%/*}" && printf "%s\n" "$1" > "$0"' $preset_file $cfg.preset] --creates $preset_file
                --then (unit-restart $UNIT --reload --if-running))
        })
        (unit-file $"services/($UNIT)" --values {DOTFILES: $env.DOTFILES} --enable --then (unit-restart $UNIT))
        # the daemon runs the script live from $DOTFILES: a script edit the running copy would miss restarts it
        (file-text (xdg state color-grading script-hash) $"($script_hash)\n" --generated --then (unit-restart $UNIT))
    ]
}
