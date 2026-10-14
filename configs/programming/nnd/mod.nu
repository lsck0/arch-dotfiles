use module.nu *

export const meta = {packages: {pacman: [nnd]}}

export def link [cfg: record] {
    files-into ($nu.home-dir | path join .nnd) keys
}
