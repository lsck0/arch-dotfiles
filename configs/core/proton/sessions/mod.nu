use module.nu *
use sessions.nu [sessions-backup sessions-restore sessions-settled MARKER]

export const meta = {packages: {pacman: [python-secretstorage sqlite]}, backup: {secrets: true}, volatile: true}

const PASS_DESKTOP = "proton-pass.desktop"

def archives []: nothing -> path {
    host-file ($env.DOTFILES | path join configs secrets keys proton)
}

# What the login unit would do, for an apply in a session; once settled only the unit file stays.
export def link [cfg: record] {
    if not (owner-unlocked) { return [] }
    [
        # pass picks its cookie store from the desktop (basic under hyprland, kwallet under plasma): pinned to the one
        # a reinstall can carry without a keyring
        (desktop-override $PASS_DESKTOP {
            $in | str replace --all --regex '(?m)^(Exec=proton-pass) ' '$1 --password-store=basic '
        })
        (link-commands proton-sessions-restore.nu)
        (unit-file proton-sessions-restore.service --enable)
        (if (xdg state $MARKER | path exists) { [] } else { step sessions-restore-now })
    ]
}

export def sessions-restore-now []: nothing -> nothing {
    let statuses = sessions-restore (archives)
    for row in ($statuses | where status in [restored locked waiting]) {
        log-info $"proton-sessions: ($row.app) ($row.status)"
    }
    if (sessions-settled $statuses) {
        mkdir (xdg state $MARKER | path dirname)
        touch (xdg state $MARKER)
    }
}

export def backup [cfg: record]: nothing -> nothing {
    sessions-backup (archives) | where status != saved | each {|row| print -e $"proton-sessions: ($row.app): ($row.status)" } | ignore
}

export def restore [cfg: record] {
    sessions-restore-now
}
