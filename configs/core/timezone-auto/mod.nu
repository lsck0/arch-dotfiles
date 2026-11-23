use module.nu *

const NM_DISPATCHER_DIR = "/etc/NetworkManager/dispatcher.d"

export def link [cfg: record] {
    [
        (unit-file timezone-auto.service --values {DIR: $env.PWD})
        (unit-timer timezone-auto.timer "Check the system timezone after boot" --startup 2min
            --accuracy 5min --enable --now)
    ]
}

export def system [cfg: record] {
    [
        (polkit-rules 49-timezone-auto.rules)
        (if ($NM_DISPATCHER_DIR | path exists) {
            file-copy nm-dispatcher.nu ($NM_DISPATCHER_DIR | path join 85-timezone-auto) --mode 755
        })
    ]
}
