use module.nu *

export const meta = {
    packages: {pacman: [kani]}
    # two rustup runs at once race on its download and settings files
    serial: true
}

export def link [cfg: record] {
    # cargo-kani would run its whole first-time setup just to print its version
    let version = package-version kani
    if $version == null { return [] }
    exec kani-setup [cargo kani setup] --creates ($nu.home-dir | path join .kani $"kani-($version)") --network
}
