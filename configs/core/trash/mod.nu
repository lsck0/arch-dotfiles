use module.nu *

export const meta = {packages: {pacman: [trash-cli]}}

export def link [cfg: record] {
    [(unit-file trash-empty.service) (unit-file trash-empty.timer --enable --now)]
}
