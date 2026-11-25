use module.nu *

export const meta = {packages: {pacman: [fastfetch]}}

export const options = {
    on_shell_start: {
        type: bool
        default: true
        doc: "Run fastfetch (system summary, local address) atop each new top-level terminal, zsh and nushell"
        label: "Fetch on shell start"
        scope: user
    }
}

export def link [cfg: record] {
    file-copy config/fastfetch.jsonc (xdg config fastfetch config.jsonc)
}
