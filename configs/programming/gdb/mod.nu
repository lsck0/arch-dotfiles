use module.nu *

export const meta = {packages: {pacman: [gdb]}}

export def link [cfg: record] {
    file-copy config/gdbinit (xdg config gdb gdbinit)
}
