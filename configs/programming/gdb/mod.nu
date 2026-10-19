use module.nu *

export const meta = {packages: {pacman: [gdb]}}

export def link [cfg: record] {
    file-copy gdbinit ($nu.home-dir | path join .config gdb gdbinit)
}
