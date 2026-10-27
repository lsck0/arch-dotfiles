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

export const options = {
    sccache_redis: {
        type: bool
        default: false
        doc: "Compile through sccache with the homelab's shared redis cache (secret sccache.env); plain rustc whenever it is unreachable"
        label: "Shared sccache"
    }
}

const SECRET = "configs/secrets/keys/sccache.env"

export def link [cfg: record] {
    let cargo = $nu.home-dir | path join .cargo
    let secret = $env.DOTFILES | path join $SECRET
    let shared = $cfg.sccache_redis and (profile-has secrets) and (secret-is-plaintext $secret)
    if not $shared { return (files-into $cargo config.toml) }
    let s = open --raw $secret | lines | parse --regex '^(?<k>[A-Z_]+)=(?<v>.*)$'
        | reduce --fold {} {|e, acc| $acc | insert $e.k ($e.v | str trim) }
    let url = $s.SCCACHE_REDIS_ENDPOINT | url parse
    let wrapper = $nu.home-dir | path join .local bin rustc-wrapper
    [
        (file-text (xdg config sccache config) $"[cache.redis]\nendpoint = \"redis://($url.host):($url.port)\"\npassword = \"($s.SCCACHE_REDIS_PASSWORD)\"\n" --mode 600)
        (file-render rustc-wrapper.sh $wrapper {HOST: $url.host, PORT: $url.port} --mode 755)
        (file-text ($cargo | path join config.toml) $"(open --raw config.toml)\n[build]\nrustc-wrapper = \"($wrapper)\"\n")
    ]
}
