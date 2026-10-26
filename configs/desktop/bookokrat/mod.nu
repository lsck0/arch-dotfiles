use module.nu *

export const meta = {packages: {pacman: [bookokrat-bin]}}

export def link [cfg: record] {
    let dest = xdg config bookokrat config.yaml
    exec bookokrat-seed [install -Dm644 config.yaml $dest] --creates $dest
}
