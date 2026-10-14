use module.nu *

export const meta = {packages: {pacman: [starship]}}

export def link [cfg: record] {
    files-into ($nu.home-dir | path join .config) starship.toml
}
