use module.nu *

export const meta = {
    packages: {pacman: [kani]}
    # rustup installs toolchains, and two rustup runs at once race on its download and settings files
    serial: true
    inputs: [/usr/bin/cargo-kani]
}

export def link [cfg: record] {
    if (which cargo-kani | is-empty) { return [] }
    # "kani 0.64.0-1"; cargo-kani itself would run its whole first-time setup just to print its version
    let version = ^pacman -Q kani | split row " " | get 1 | split row "-" | first
    exec kani-setup [cargo kani setup] --creates ($nu.home-dir | path join .kani $"kani-($version)")
}
