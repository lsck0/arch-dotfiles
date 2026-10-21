use module.nu *

const OOMD = "/usr/lib/systemd/system/systemd-oomd.service"
const SESSION_LOW_MAX = 2GiB
const SESSION_LOW_PERCENT = 15

export const options = {
    session_memory_low: {
        type: filesize?
        default: null
        doc: "session.slice's MemoryLow, the desktop working set a build's reclaim keeps; null: 15% of RAM, 2 GiB max"
        label: "Desktop memory reserve"
        scope: machine
    }
}

def systemd-size [value: any]: nothing -> string {
    let size = $value | into filesize
    if ($size mod 1GiB) == 0B { $"($size // 1GiB)G" } else { $"($size // 1MiB)M" }
}

export def detect [cfg: record]: nothing -> record {
    {session_memory_low: ([$SESSION_LOW_MAX ((sys mem).total * $SESSION_LOW_PERCENT / 100)] | math min)}
}

export def system [cfg: record] {
    if not ($OOMD | path exists) { return [] }
    [
        (unit-enable systemd-oomd.service --now)
        (file-copy oomd.conf /etc/systemd/oomd.conf.d/10-oomd.conf --then [systemctl try-restart systemd-oomd.service])
        # protection reaches session.slice only through every ancestor slice
        (dropin user.slice user-protect.slice.conf --name 10-protect.conf)
        (dropin user-.slice user-protect.slice.conf --name 10-protect.conf)
        (dropin user@.service user-protect.service.conf --name 10-protect.conf)
    ]
}

export def link [cfg: record] {
    if not ($OOMD | path exists) { return [] }
    [
        (dropin app.slice oomd-app.slice.conf --name 10-oomd.conf)
        (file-render session-protect.slice.conf (unit-dir | path join session.slice.d 10-protect.conf)
            {MEMORY_LOW: (systemd-size $cfg.session_memory_low)})
        (file-render oom-notify.service (unit-dir | path join oom-notify.service) {DOTFILES: $env.DOTFILES})
        (unit-enable oom-notify.service --now)
    ]
}
