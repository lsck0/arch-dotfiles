use module.nu *

export const meta = {packages: {pacman: [nsxiv]}}

export def link [cfg: record] {
    file-copy exec/key-handler ($nu.home-dir | path join .config nsxiv exec key-handler) --mode 755
}
