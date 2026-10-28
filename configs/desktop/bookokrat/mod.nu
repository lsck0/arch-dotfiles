use module.nu *

export const meta = {packages: {pacman: [bookokrat-bin]}}

export def link [cfg: record] {
    let dest = xdg config bookokrat config.yaml
    # seeded once: bookokrat rewrites config.yaml at runtime, so a repo edit only reaches a fresh install
    exec bookokrat-seed [install -Dm644 config.yaml $dest] --creates $dest
}
