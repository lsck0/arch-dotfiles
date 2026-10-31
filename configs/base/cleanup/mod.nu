use module.nu *

export const options = {
    journal_max_use: {
        type: string
        default: "500M"
        doc: "Total disk space the systemd journal may keep, journald.conf(5) size syntax"
        label: "Max journal size"
    }
}

export def system [cfg: record] {
    (
        file-render journald-size.conf /etc/systemd/journald.conf.d/00-size.conf {MAX_USE: $cfg.journal_max_use}
            --then [systemctl restart systemd-journald.service]
    )
}

export def link [cfg: record] {
    [
        (link-commands home-sweep.nu)
        (unit-file home-sweep.service)
        (unit-file home-sweep.timer --enable --now)
    ] ++ (if (which nix-collect-garbage | is-empty) { [] } else {
        [(unit-file nix-gc.service) (unit-file nix-gc.timer --enable --now)]
    })
}
