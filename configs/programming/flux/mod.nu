use module.nu *

export const meta = {
    packages: {pacman: [flux-rs liquid-fixpoint]}
    # two rustup runs at once race on its download and settings files
    serial: true
    # rustup's default home; the toolchains dir changes on every install, so the run after one plans the drop
    inputs: [/usr/lib/flux/rust-toolchain.toml ~/.rustup/toolchains]
}

const SYSROOT = "/usr/lib/flux"
const TRIPLE = "x86_64-unknown-linux-gnu"

def toolchain-dir [rustup: path, name: string]: nothing -> path { $rustup | path join toolchains $"($name)-($TRIPLE)" }

export def link [cfg: record] {
    let toolchain = $SYSROOT | path join rust-toolchain.toml
    if not ($toolchain | path exists) or (which rustup | is-empty) { return [] }
    let spec = open $toolchain | get toolchain
    let channel = $spec.channel
    let components = $spec.components | str join ','
    let rustup = $env.RUSTUP_HOME? | default ($nu.home-dir | path join .rustup)
    let marker = toolchain-dir $rustup $channel | path join lib rustlib $"manifest-llvm-tools-preview-($TRIPLE)"
    let stamp = xdg state flux toolchain
    let previous = if ($stamp | path exists) { open --raw $stamp | str trim } else { "" }
    let installed = $marker | path exists
    # only flux's own previous pin is dropped: other nightlies may belong to other projects
    let stale = ($installed and $previous != "" and $previous != $channel
        and (toolchain-dir $rustup $previous | path exists))
    [
        (exec flux-toolchain [rustup toolchain install $channel --profile minimal --component $components] --creates $marker)
        (if $stale { [(exec $"flux-toolchain-drop ($previous)" [rustup toolchain uninstall $previous])] } else { [] })
        (if $installed { [(file-text $stamp $"($channel)\n" --generated)] } else if $previous != "" {
            [(file-text $stamp $"($previous)\n" --generated)]
        } else { [] })
    ]
}
