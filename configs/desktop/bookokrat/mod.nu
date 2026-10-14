use module.nu *

export const meta = {packages: {pacman: [bookokrat-bin]}}

# a seed only: bookokrat writes its own state into this file
export def link [cfg: record] {
    let dest = $nu.home-dir | path join .config bookokrat config.yaml
    exec bookokrat-seed [install -Dm644 config.yaml $dest] --creates $dest
}
