use module.nu *

export const meta = {packages: {pacman: [asm-lsp]}}

export def link [cfg: record] {
    files-into ($nu.home-dir | path join .config asm-lsp) .asm-lsp.toml
}
