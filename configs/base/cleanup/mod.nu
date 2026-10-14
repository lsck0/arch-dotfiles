use module.nu *

# a journald restart rotates the journal, so only on change
export def system [cfg: record] {
    (
        file-copy journald-size.conf /etc/systemd/journald.conf.d/00-size.conf
            --then [systemctl restart systemd-journald.service]
    )
}

export def link [cfg: record] {
    [
        (link-commands home-sweep.nu)
        (unit-file home-sweep.service)
        (unit-file home-sweep.timer --enable --now)
    ] ++ (if (which nix | is-empty) { [] } else {
        # as the profile owner: expires its generations, the daemon collects the store
        [(unit-file nix-gc.service) (unit-file nix-gc.timer --enable --now)]
    })
}
