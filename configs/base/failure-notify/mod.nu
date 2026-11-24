use module.nu *

export const meta = {packages: {pacman: [arch-audit lynis]}}

export def system [cfg: record] {
    if (which lynis | is-empty) { return [] }
    [
        (file-copy scripts/lynis-audit.nu /usr/local/bin/lynis-audit --mode 755)
        (unit-file config/lynis-audit.service)
        (unit-timer lynis-audit.timer "Monthly lynis security audit" --calendar monthly --delay 1h
            --ac-power 99-lynis-ac.rules --enable --now)
        (udev-rules config/99-lynis-ac.rules)
    ]
}

export def link [cfg: record] {
    if (which notify-send | is-empty) { return [] }
    [
        # the handler must not be its own OnFailure=
        (dropin service config/failure-notify.conf --name 10-failure-notify.conf)
        (file-link /dev/null (unit-dir | path join failure-notify@.service.d 10-failure-notify.conf))
        (link-commands scripts/system-notify.nu scripts/update-check.nu scripts/doctor-check.nu)
        (unit-file config/failure-notify@.service)
        (unit-file config/system-notify.service)
        (unit-file config/update-check.service)
        (unit-timer update-check.timer "Daily check for package updates and security advisories" --calendar daily
            --delay 1h)
        (unit-file config/doctor-check.service)
        (unit-timer doctor-check.timer "Hourly check of this machine against its declared state" --boot 5min --every 1h
            --delay 5min)
        (unit-file config/recovery-drill.service)
        (unit-timer recovery-drill.timer "Monthly look whether the paper-key recovery drill is due" --calendar monthly
            --delay 1h)
        # not --now: the notice belongs to the next login, not the middle of a run
        (unit-file config/failures-login.service --values {DOTFILES: $env.DOTFILES} --enable)
        (unit-enable system-notify.service --now)
        (unit-switch update-check.timer (which checkupdates | is-not-empty))
        (unit-enable doctor-check.timer)
        (unit-switch recovery-drill.timer (profile-has secrets))
    ]
}
