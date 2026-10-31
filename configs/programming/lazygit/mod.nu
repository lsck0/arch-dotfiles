use module.nu *

export const meta = {packages: {pacman: [lazygit]}}

export def link [cfg: record] {
    [
        (shell-aliases lazygit)
        (files-into (xdg config lazygit) config.yml)
    ]
}
