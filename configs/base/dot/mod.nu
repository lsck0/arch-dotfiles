use complete.nu [completions-zsh]
use module.nu *

# git-lfs: bootstrap installs it and run.nu pulls the repo's lfs objects with it, on a machine without core/git too
export const meta = {
    packages: {pacman: [git-lfs]}
    inputs: [scripts/dot.nu scripts/lib/dot-cli.nu scripts/lib/internal.nu scripts/lib/complete.nu scripts/lib/usage.nu]
}

export def link [cfg: record] {
    let dot = $env.DOTFILES | path join scripts dot.nu
    let data = xdg data
    # the nushell externs come from dot-cli.nu's own command table, which only a dot process has in scope
    [
        (file-text ($data | path join zsh site-functions _dot) (completions-zsh | str trim --right) --generated)
        (file-text ($data | path join nushell vendor autoload dot.nu) (^nu --no-config-file $dot internal completions nu) --generated)
    ]
}
