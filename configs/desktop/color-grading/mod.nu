use module.nu *

const UNIT = "color-grading.service"
const SCRIPT = path self color-grading.py

export def link [cfg: record] {
    let script_hash = open --raw $SCRIPT | hash sha256
    [
        (file-render $UNIT (unit-dir | path join $UNIT) {DOTFILES: $env.DOTFILES} --then (unit-restart $UNIT))
        (unit-enable $UNIT)
        # the daemon runs the script live from $DOTFILES: a script edit the running copy would miss restarts it
        (file-text (xdg state color-grading script-hash) $"($script_hash)\n" --generated --then (unit-restart $UNIT))
    ]
}
