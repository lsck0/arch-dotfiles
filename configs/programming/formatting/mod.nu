use module.nu *

export const meta = {
    packages: {pacman: [kulala-fmt prettier rustup shellcheck shfmt stylua taplo-cli typstyle]}
    # two rustup runs at once race on its download and settings files
    serial: true
}

export def link [cfg: record] {
    let latexindent = xdg config latexindent latexindent.yaml
    let rustup = $env.RUSTUP_HOME? | default ($nu.home-dir | path join .rustup)
    [
        (exec rustfmt-nightly [rustup toolchain install nightly --profile minimal --component rustfmt]
            --creates ($rustup | path join toolchains nightly-x86_64-unknown-linux-gnu bin rustfmt) --network)
        (file-copy chktexrc (xdg config chktexrc))
        (file-copy latexindent.yaml $latexindent)
        (file-text (xdg config latexindent indentconfig.yaml) $"paths:\n  - ($latexindent)\n")
    ]
}
