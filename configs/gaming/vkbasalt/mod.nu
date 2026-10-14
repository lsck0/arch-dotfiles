use module.nu *

export const meta = {packages: {pacman: [lib32-vkbasalt vkbasalt]}}

export def link [cfg: record] {
    files-into ($nu.home-dir | path join .config vkBasalt) vkBasalt.conf
}
