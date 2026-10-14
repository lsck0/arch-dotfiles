use module.nu *

export const meta = {packages: {pacman: [feather-wallet-bin]}}

# only pointed at, never created: a dir made before syncthing delivered monero/master collides with it
export def link [cfg: record] {
    json-merge ($nu.home-dir | path join .config feather settings.json) [(json-set [walletDirectory] ($nu.home-dir | path join sync monero))]
}
