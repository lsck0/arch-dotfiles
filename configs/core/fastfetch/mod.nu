use module.nu *

export const meta = {packages: {pacman: [fastfetch]}}

export def link [cfg: record] {
    file-copy fastfetch.jsonc ($nu.home-dir | path join .config fastfetch config.jsonc)
}
