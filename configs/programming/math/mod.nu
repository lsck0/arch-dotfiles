use module.nu *

export const meta = {packages: {pacman: [ecgen gap genius gnuplot r rstudio-desktop-bin sagemath topology-toolkit], nix: [macaulay2]}}

export def link [cfg: record] {
    if (which rstudio | is-empty) { return [] }
    json-merge ($nu.home-dir | path join .config rstudio config.json) [(json-set [view showWhatsNew] false)]
}
