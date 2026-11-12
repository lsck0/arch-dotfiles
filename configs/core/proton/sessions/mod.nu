use module.nu *
use sessions.nu [sessions-archives sessions-backup sessions-restore sessions-settle MARKER]

export const meta = {packages: {pacman: [python-secretstorage sqlite]}, backup: {secrets: true}, volatile: true}

const PASS_DESKTOP = "proton-pass.desktop"

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
        # reenable: a changed WantedBy leaves the old target's wants link behind
        (unit-file proton-sessions-restore.service --enable --then [systemctl --user reenable proton-sessions-restore.service])
        (step sessions-restore-now --creates (xdg state $MARKER))
    ]
}

export def sessions-restore-now []: nothing -> nothing {
    let statuses = sessions-restore (sessions-archives $env.DOTFILES)
    for row in ($statuses | where status in [restored locked waiting]) {
        log-info $"proton-sessions: ($row.app) ($row.status)"
    }
    sessions-settle $statuses
}

export def backup [cfg: record]: nothing -> nothing {
    for row in (sessions-backup (sessions-archives $env.DOTFILES) | where status != saved) {
        print -e $"proton-sessions: ($row.app): ($row.status)"
    }
}

export def restore [cfg: record] {
    sessions-restore-now
}
