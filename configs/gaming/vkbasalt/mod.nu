use module.nu *

export const meta = {packages: {pacman: [lib32-vkbasalt vkbasalt]}}

export def link [cfg: record] {
    files-into (xdg config vkBasalt) vkBasalt.conf
}
