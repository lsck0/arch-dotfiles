use module.nu *

# pkexec may run the root-owned system-apply.nu, and nothing else, for a session without a terminal (dot set from the
# settings window). auth_admin, never kept: the archive it applies is root code, so every apply asks
export def system [cfg: record] {
    file-copy dev.lsck0.dotfiles.policy /usr/share/polkit-1/actions/dev.lsck0.dotfiles.policy
}
