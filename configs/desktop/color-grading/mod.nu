use module.nu *

export const meta = {packages: {pacman: [python]}}

const UNIT = "color-grading.service"
const SCRIPT = path self scripts/color-grading.py

export def link [cfg: record] {
    let script_hash = open --raw $SCRIPT | hash sha256
    [
        (unit-file $"services/($UNIT)" --values {DOTFILES: $env.DOTFILES} --enable --then (unit-restart $UNIT))
        # the daemon runs the script live from $DOTFILES: a script edit the running copy would miss restarts it
        (file-text (xdg state color-grading script-hash) $"($script_hash)\n" --generated --then (unit-restart $UNIT))
    ]
}
