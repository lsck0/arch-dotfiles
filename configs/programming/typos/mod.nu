use module.nu *

export const meta = {packages: {pacman: [typos]}}

export def link [cfg: record] {
    files-into (xdg config typos) typos.toml
}
