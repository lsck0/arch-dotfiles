use module.nu *

export const meta = {
    packages: {pacman: [fzf-tab-git oh-my-zsh-git zsh zsh-autosuggestions zsh-completions zsh-syntax-highlighting]}
}

# the login shell is set at user creation (bootstrap, adduser-dotfiles), not here
export def link [cfg: record] {
    [
        (file-copy zshrc ($nu.home-dir | path join .zshrc))
        # every zsh (login, interactive, non-interactive) sources environment.d, so agents' tty shells match systemd
        (file-copy zshenv ($nu.home-dir | path join .zshenv))
        # a command, not a zsh function: agents run builds from non-interactive shells
        (link-commands fence.nu)
        # systemd's user manager hands it to every unit and graphical app, zshrc to tty and ssh logins
        (files-into ($env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join environment.d) no-telemetry.conf)
    ]
}
