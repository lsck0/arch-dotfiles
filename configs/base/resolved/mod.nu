use module.nu *

export const meta = {packages: {pacman: [systemd-resolvconf]}, native_only: [system]}

export def system [cfg: record] {
    [
        # a reload keeps the per-link dns NetworkManager pushed (the homelab's split dns); a restart drops it until the
        # link's next change
        (file-copy resolved.conf /etc/systemd/resolved.conf.d/dotfiles.conf
            --then (unit-restart systemd-resolved.service --reload))
        (file-link /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf)
        (unit-enable systemd-resolved.service --now)
    ]
}
