use module.nu *

export const meta = {packages: {pacman: [typos]}}

export def link [cfg: record] {
    files-into ($nu.home-dir | path join .config typos) typos.toml
}
