use module.nu *

export const meta = {
    packages: {pacman: [kani]}
    # rustup installs toolchains, and two rustup runs at once race on its download and settings files
    serial: true
    inputs: [/usr/bin/cargo-kani]
}

export def link [cfg: record] {
    if (which cargo-kani | is-empty) { return [] }
    # "cargo-kani 0.64.0"
    let version = ^cargo-kani --version | lines | first | split row " " | get 1
    exec kani-setup [cargo kani setup] --creates ($nu.home-dir | path join .kani $"kani-($version)")
}
