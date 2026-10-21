use module.nu *

export const meta = {
    packages: {pacman: [fzf-tab-git oh-my-zsh-git zsh zsh-autosuggestions zsh-completions zsh-syntax-highlighting]}
}

export def link [cfg: record] {
    [
        (file-copy zshrc ($nu.home-dir | path join .zshrc))
        (file-copy zshenv ($nu.home-dir | path join .zshenv))
        (link-commands fence.nu)
        (files-into ($env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join environment.d) no-telemetry.conf)
    ]
}
