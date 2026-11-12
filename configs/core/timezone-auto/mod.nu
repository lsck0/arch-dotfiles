use module.nu *

const NM_DISPATCHER_DIR = "/etc/NetworkManager/dispatcher.d"

export def link [cfg: record] {
    [
        (file-render timezone-auto.service (unit-dir | path join timezone-auto.service) {DIR: $env.PWD})
        (unit-file timezone-auto.timer --enable --now)
    ]
}

export def system [cfg: record] {
    [
        (file-copy 49-timezone-auto.rules /etc/polkit-1/rules.d/49-timezone-auto.rules)
        (if ($NM_DISPATCHER_DIR | path exists) {
            file-copy nm-dispatcher.nu ($NM_DISPATCHER_DIR | path join 85-timezone-auto) --mode 755
        })
    ]
}
