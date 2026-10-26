use module.nu *

export const meta = {packages: {pacman: [lazygit]}}

export def link [cfg: record] {
    files-into (xdg config lazygit) config.yml
}
