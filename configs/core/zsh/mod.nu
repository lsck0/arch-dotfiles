use module.nu *

export const meta = {
    packages: {pacman: [fzf-tab-git oh-my-zsh-git zsh zsh-autosuggestions zsh-completions zsh-syntax-highlighting]}
}

export def link [cfg: record] {
    [
        (file-copy config/zshrc ($nu.home-dir | path join .zshrc))
        (file-copy config/zshenv ($nu.home-dir | path join .zshenv))
        (link-commands scripts/fence.sh)
        (files-into (xdg config environment.d) config/no-telemetry.conf)
    ]
}
