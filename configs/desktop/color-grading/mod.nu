use module.nu *

const UNIT = "color-grading.service"

export def link [cfg: record] {
    [
        (file-render $UNIT (unit-dir | path join $UNIT) {DOTFILES: $env.DOTFILES})
        (unit-enable $UNIT)
        # outside a session (a fresh install from a tty) nothing runs, the next login starts it
        (exec color-grading-restart [systemctl --user try-restart $UNIT])
    ]
}
