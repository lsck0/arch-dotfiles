use module.nu *

export const meta = {
    packages: {pacman: [flux-rs liquid-fixpoint]}
    # two rustup runs at once race on its download and settings files
    serial: true
    inputs: [/usr/lib/flux/rust-toolchain.toml]
}

const SYSROOT = "/usr/lib/flux"

export def link [cfg: record] {
    let toolchain = $SYSROOT | path join rust-toolchain.toml
    if not ($toolchain | path exists) or (which rustup | is-empty) { return [] }
    let spec = open $toolchain | get toolchain
    let channel = $spec.channel
    let components = $spec.components | str join ','
    let rustup = $env.RUSTUP_HOME? | default ($nu.home-dir | path join .rustup)
    let marker = $rustup | path join toolchains $"($channel)-x86_64-unknown-linux-gnu" lib rustlib manifest-llvm-tools-preview-x86_64-unknown-linux-gnu
    # flux reads FLUX_SYSROOT (app-dirs.conf) for its sysroot, so no ~/.flux link is needed
    [
        (exec flux-toolchain [rustup toolchain install $channel --profile minimal --component $components] --creates $marker)
    ]
}
