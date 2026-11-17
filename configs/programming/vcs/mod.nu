use module.nu *

export const meta = {
    packages: {
        pacman: [
            difftastic git-absorb git-age git-filter-repo git-lfs github-cli github-desktop-bin jujutsu lazyjj mergiraf
            onefetch pre-commit tig
        ]
    }
}

export def link [cfg: record] {
    [
        (shell-aliases vcs)
        # its bundled electron predates 38 and would run on scaled xwayland, unlike every other electron app here
        (desktop-override github-desktop.desktop {
            str replace --all --regex "(?m)^Exec=/usr/bin/github-desktop " "Exec=/usr/bin/github-desktop --ozone-platform-hint=auto "
        })
    ]
}
