use module.nu *

# the formatter configs are not placed: the editors pass them only to projects without their own
export const meta = {
    packages: {pacman: [kulala-fmt prettier shellcheck shfmt stylua taplo-cli typstyle]}
    # rustup installs toolchains, and two rustup runs at once race on its download and settings files
    serial: true
}

export def link [cfg: record] {
    let latexindent = $nu.home-dir | path join .config latexindent latexindent.yaml
    let rustup = $env.RUSTUP_HOME? | default ($nu.home-dir | path join .rustup)
    [
        # rustfmt.toml sets nightly-only options, so the editors run it through `rustfmt +nightly`
        (exec rustfmt-nightly [rustup toolchain install nightly --profile minimal --component rustfmt]
            --creates ($rustup | path join toolchains nightly-x86_64-unknown-linux-gnu bin rustfmt))
        (file-copy chktexrc ($nu.home-dir | path join .chktexrc))
        (file-copy latexindent.yaml $latexindent)
        # latexindent finds its config only through this file
        (file-text ($nu.home-dir | path join .indentconfig.yaml) $"paths:\n  - ($latexindent)\n")
    ]
}
