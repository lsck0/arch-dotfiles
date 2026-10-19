use module.nu *

export const meta = {inputs: [scripts/dot.nu scripts/lib/internal.nu scripts/lib/complete.nu]}

export def link [cfg: record] {
    let dot = $env.DOTFILES | path join scripts dot.nu
    let data = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share)
    [
        (file-text ($data | path join zsh site-functions _dot) (^nu --no-config-file $dot internal completions zsh) --generated)
        (file-text ($data | path join nushell vendor autoload dot.nu) (^nu --no-config-file $dot internal completions nu) --generated)
    ]
}

# auth_admin, never kept: the archive pkexec applies is root code, so every apply asks
export def system [cfg: record] {
    file-copy dev.lsck0.dotfiles.policy /usr/share/polkit-1/actions/dev.lsck0.dotfiles.policy
}
