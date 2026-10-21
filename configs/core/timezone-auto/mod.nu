use module.nu *

export def link [cfg: record] {
    [
        (file-render timezone-auto.service (unit-dir | path join timezone-auto.service) {DIR: $env.PWD})
        (unit-file timezone-auto.timer --enable --now)
    ]
}

export def system [cfg: record] {
    let dispatcher = "/etc/NetworkManager/dispatcher.d"
    [
        (file-copy 49-timezone-auto.rules /etc/polkit-1/rules.d/49-timezone-auto.rules)
        (if ($dispatcher | path exists) {
            file-copy nm-dispatcher.nu ($dispatcher | path join 85-timezone-auto) --mode 755
        } else { [] })
    ]
}
