use module.nu *

# auth_admin, never kept: the archive pkexec applies is root code, so every apply asks
export def system [cfg: record] {
    file-copy dev.lsck0.dotfiles.policy /usr/share/polkit-1/actions/dev.lsck0.dotfiles.policy
}
