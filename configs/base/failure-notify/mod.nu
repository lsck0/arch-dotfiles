use module.nu *

export const meta = {packages: {pacman: [arch-audit lynis]}}

const UNITS = [
    failure-notify@.service failures-login.service system-notify.service update-check.service update-check.timer
    doctor-check.service doctor-check.timer recovery-drill.service recovery-drill.timer
]

# a monthly lynis audit, reported through the journal to each admin's system-notify
export def system [cfg: record] {
    if (which lynis | is-empty) { return [] }
    [
        (file-copy lynis-audit.nu /usr/local/bin/lynis-audit --mode 755)
        (unit-file lynis-audit.service)
        (unit-file lynis-audit.timer --enable)
    ]
}

def timer-if [name: string, wanted: bool]: nothing -> record {
    if $wanted { unit-enable $name } else { unit-disable $name }
}

export def link [cfg: record] {
    if (which notify-send | is-empty) { return [] }
    [
        # OnFailure= for every user service; the handler must not be its own OnFailure=
        (dropin service failure-notify.conf --name 10-failure-notify.conf)
        (file-link /dev/null (unit-dir | path join failure-notify@.service.d 10-failure-notify.conf))
        (link-commands system-notify.nu update-check.nu doctor-check.nu)
        ($UNITS | each { unit-file $in } | decls-flatten)
        # not --now: the notice belongs to the next login, not the middle of a run
        (unit-enable failures-login.service)
        # system units, smartd and lynis-audit report through the system journal, which wheel reads
        (unit-enable system-notify.service --now)
        (timer-if update-check.timer (which checkupdates | is-not-empty))
        # dot doctor hourly, into the bar's doctor indicator and a notification when its findings change
        (unit-enable doctor-check.timer)
        # only whoever holds the paper key can drill it
        (timer-if recovery-drill.timer (profile-has secrets))
    ]
}
