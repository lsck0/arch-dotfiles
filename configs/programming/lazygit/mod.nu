use module.nu *

export const meta = {packages: {pacman: [lazygit]}}

export def link [cfg: record] {
    [
        (shell-aliases lazygit)
        # --config instead of git's: core/git's theme colours, without its [delta] navigate, which breaks in lazygit
        (file-render config.yml (xdg config lazygit config.yml) {DELTA_CONFIG: (xdg cache wal delta.gitconfig)})
    ]
}
