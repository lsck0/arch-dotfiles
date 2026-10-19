use module.nu *

# latexindent's perl deps are texlive optdepends, not pulled on their own
export const meta = {
    packages: {
        pacman: [biber bibiman-bin lyx perl-file-homedir perl-yaml-tiny tectonic texlab texlive texlive-lang texmaker]
    }
}

export def link [cfg: record] {
    file-copy latexmkrc ($nu.home-dir | path join .config latexmk latexmkrc)
}
