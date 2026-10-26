use module.nu *

export const meta = {packages: {pacman: [nsxiv]}}

export def link [cfg: record] {
    file-copy exec/key-handler (xdg config nsxiv exec key-handler) --mode 755
}
