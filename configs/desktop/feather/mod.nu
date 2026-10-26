use module.nu *

export const meta = {packages: {pacman: [feather-wallet-bin]}}

export def link [cfg: record] {
    # only pointed at, never created: a dir made before syncthing delivers it would collide
    json-merge (xdg config feather settings.json) [(json-set [walletDirectory] ($nu.home-dir | path join sync monero))]
}
