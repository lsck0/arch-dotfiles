use module.nu *

export const meta = {
    packages: {pacman: [kulala-fmt prettier shellcheck shfmt stylua taplo-cli typstyle]}
    # two rustup runs at once race on its download and settings files
    serial: true
}

export def link [cfg: record] {
    let latexindent = $nu.home-dir | path join .config latexindent latexindent.yaml
    let rustup = $env.RUSTUP_HOME? | default ($nu.home-dir | path join .rustup)
    [
        (exec rustfmt-nightly [rustup toolchain install nightly --profile minimal --component rustfmt]
            --creates ($rustup | path join toolchains nightly-x86_64-unknown-linux-gnu bin rustfmt))
        (file-copy chktexrc ($nu.home-dir | path join .config chktexrc))
        (file-copy latexindent.yaml $latexindent)
        (file-text ($nu.home-dir | path join .config latexindent indentconfig.yaml) $"paths:\n  - ($latexindent)\n")
    ]
}
