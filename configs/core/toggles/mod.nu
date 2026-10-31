use module.nu *

export const meta = {packages: {pacman: [polkit]}}

export def system [cfg: record] {
    [
        (file-copy toggle-root.nu /usr/local/bin/toggle-root --mode 755)
        (file-copy 49-toggles.rules /etc/polkit-1/rules.d/49-toggles.rules)
    ]
}
