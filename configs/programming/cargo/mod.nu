use module.nu *

export const meta = {
    packages: {
        pacman: [
            bacon cargo-afl cargo-audit cargo-bloat cargo-deny cargo-edit cargo-expand cargo-flamegraph cargo-fuzz
            cargo-generate cargo-info cargo-leptos cargo-llvm-cov cargo-make cargo-mutants cargo-nextest cargo-seek
            cargo-shear cargo-show-asm cargo-shuttle cargo-sort-derives cargo-update cargo-wizard cargo-zigbuild
            crates-tui-git cross diesel-cli irust leptosfmt rustfilt sccache sqlx-cli tauri-cli trunk
        ]
    }
}

export def link [cfg: record] {
    files-into ($nu.home-dir | path join .cargo) config.toml
}
