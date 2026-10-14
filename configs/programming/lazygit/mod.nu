use module.nu *

export const meta = {packages: {pacman: [lazygit]}}

export def link [cfg: record] {
    files-into ($nu.home-dir | path join .config lazygit) config.yml
}
