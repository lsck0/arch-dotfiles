use module.nu *

export const meta = {packages: {pacman: [feather-wallet-bin]}}

# wallets live in the syncthing folder (the homelab and its offsite backup hold them, the .keys stay
# password-encrypted); only pointed at, never created: a dir made before syncthing delivered monero/master collides
export def link [cfg: record] {
    json-merge ($nu.home-dir | path join .config feather settings.json) [(json-set [walletDirectory] ($nu.home-dir | path join sync monero))]
}
