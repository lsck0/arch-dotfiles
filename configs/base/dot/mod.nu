use complete.nu [completions-zsh]
use module.nu *

export const meta = {inputs: [scripts/dot.nu scripts/lib/internal.nu scripts/lib/complete.nu]}

export def link [cfg: record] {
    let dot = $env.DOTFILES | path join scripts dot.nu
    let data = (xdg data)
    # the nushell externs come from dot.nu's own command table, which only a dot process has in scope
    [
        (file-text ($data | path join zsh site-functions _dot) (completions-zsh | str trim --right) --generated)
        (file-text ($data | path join nushell vendor autoload dot.nu) (^nu --no-config-file $dot internal completions nu) --generated)
    ]
}

export def system [cfg: record] {
    file-copy dev.lsck0.dotfiles.policy /usr/share/polkit-1/actions/dev.lsck0.dotfiles.policy
}
