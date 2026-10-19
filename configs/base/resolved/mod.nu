use module.nu *

export const meta = {packages: {pacman: [systemd-resolvconf]}}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    [
        (file-copy resolved.conf /etc/systemd/resolved.conf.d/dotfiles.conf
            --then [systemctl restart systemd-resolved.service])
        (file-link /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf)
        (unit-enable systemd-resolved.service --now)
    ]
}
