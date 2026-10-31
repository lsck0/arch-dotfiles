use module.nu *

export const meta = {packages: {pacman: [opam]}}

export def link [cfg: record] {
    let root = $env.OPAMROOT? | default ($nu.home-dir | path join .opam)
    exec opam-init [opam init --no-setup] --creates ($root | path join config) --network
}

export def update [cfg: record]: nothing -> nothing {
    ^opam update
    ^opam upgrade -y
}
