use module.nu *

export const meta = {packages: {pacman: [asm-lsp]}}

export def link [cfg: record] {
    files-into (xdg config asm-lsp) config/.asm-lsp.toml
}
