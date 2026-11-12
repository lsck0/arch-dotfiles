use module.nu *

export const meta = {
    packages: {
        pacman: [
            bacon cargo-afl cargo-audit cargo-bloat cargo-deny cargo-edit cargo-expand cargo-flamegraph cargo-fuzz
            cargo-generate cargo-info cargo-leptos cargo-llvm-cov cargo-make cargo-mutants cargo-nextest cargo-seek
            cargo-shear cargo-show-asm cargo-shuttle cargo-sort-derives cargo-update cargo-wizard cargo-zigbuild
            crates-tui-git cross diesel-cli irust leptosfmt openbsd-netcat rustfilt sccache sqlx-cli tauri-cli trunk
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
const REDIS_PORT = "6379"
const REDIS_TLS_PORT = "6380"

export def link [cfg: record] {
    let cargo = $nu.home-dir | path join .cargo
    let secret = $env.DOTFILES | path join $SECRET
    let shared = $cfg.sccache_redis and (profile-has secrets) and (secret-is-plaintext $secret)
    if not $shared { return (files-into $cargo config.toml) }
    let s = env-file-load $secret
    let url = $s.SCCACHE_REDIS_ENDPOINT | url parse
    let port = $url.port | default --empty (if $url.scheme == rediss { $REDIS_TLS_PORT } else { $REDIS_PORT })
    let wrapper = $nu.home-dir | path join .local bin rustc-wrapper
    # a json string is a valid toml basic string
    let endpoint = $s.SCCACHE_REDIS_ENDPOINT | to json
    let password = $s.SCCACHE_REDIS_PASSWORD | to json
    [
        (file-text (xdg config sccache config) $"[cache.redis]\nendpoint = ($endpoint)\npassword = ($password)\n" --mode 600)
        (file-render rustc-wrapper.sh $wrapper {HOST: $url.host, PORT: $port} --mode 755)
        (file-text ($cargo | path join config.toml) $"(open --raw config.toml)\n[build]\nrustc-wrapper = \"($wrapper)\"\n")
    ]
}
