use module.nu *

export const meta = {packages: {pacman: [fastfetch]}}

export def link [cfg: record] {
    file-copy fastfetch.jsonc (xdg config fastfetch config.jsonc)
}
