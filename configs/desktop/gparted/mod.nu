use module.nu *

export const meta = {packages: {pacman: [gparted]}}

export def link [cfg: record] {
    desktop-override gparted.desktop { str replace --all --regex '(?m)^Exec=.*gparted.*$' 'Exec=pkexec /usr/bin/gparted %f' }
}

# the launcher entry runs gparted through pkexec; polkit asks an admin at the machine, keeping it a few minutes
export def system [cfg: record] {
    file-copy 49-gparted.rules /etc/polkit-1/rules.d/49-gparted.rules
}
