use module.nu *

export const meta = {
    packages: {pacman: [fzf-tab-git oh-my-zsh-git zsh zsh-autosuggestions zsh-completions zsh-syntax-highlighting]}
}

export const options = {
    history_size: {
        type: int
        default: 5000
        doc: "Commands the history keeps, HISTSIZE and SAVEHIST"
        label: "History size"
        min: 0
        scope: user
    }
}

export def link [cfg: record] {
    [
        (file-render config/zshrc ($nu.home-dir | path join .zshrc) {HISTORY_SIZE: $cfg.history_size})
        (file-copy config/zshenv ($nu.home-dir | path join .zshenv))
        (link-commands scripts/fence.sh)
        (files-into (xdg config environment.d) config/no-telemetry.conf)
    ]
}
