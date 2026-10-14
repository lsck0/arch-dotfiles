use module.nu *

export const meta = {packages: {pacman: [zathura zathura-pdf-mupdf]}}

export def link [cfg: record] {
    file-render zathurarc ($nu.home-dir | path join .config zathura zathurarc) {HOME: $nu.home-dir}
}
