use module.nu *

const TOOLCHAIN = "/usr/lib/flux/rust-toolchain.toml"

export const meta = {
    packages: {pacman: [flux-rs liquid-fixpoint]}
    # two rustup runs at once race on its download and settings files
    serial: true
    inputs: [$TOOLCHAIN]
}

const TRIPLE = "x86_64-unknown-linux-gnu"

# The install is named by its channel: a new pin orphans the old one, whose recorded undo uninstalls only flux's own
# previous toolchain (other nightlies may belong to other projects), as does turning the module off.
export def link [cfg: record] {
    if not ($TOOLCHAIN | path exists) or (which rustup | is-empty) { return [] }
    let spec = open $TOOLCHAIN | get toolchain
    let channel = $spec.channel
    let components = $spec.components | str join ','
    let rustup = $env.RUSTUP_HOME? | default ($nu.home-dir | path join .rustup)
    let marker = $rustup | path join toolchains $"($channel)-($TRIPLE)" lib rustlib $"manifest-llvm-tools-preview-($TRIPLE)"
    (exec $"flux-toolchain ($channel)" [rustup toolchain install $channel --profile minimal --component $components]
        --creates $marker --undo [rustup toolchain uninstall $channel] --network)
}
