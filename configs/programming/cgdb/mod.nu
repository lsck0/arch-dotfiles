use module.nu *

export const meta = {packages: {pacman: [cgdb]}}

export def link [cfg: record] {
    files-into ($nu.home-dir | path join .cgdb) cgdbrc
}
