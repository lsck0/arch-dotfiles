use module.nu *

export const meta = {
    packages: {
        pacman: [
            difftastic git-absorb git-age git-filter-repo github-cli github-desktop-bin jujutsu lazyjj mergiraf
            onefetch pre-commit tig
        ]
    }
}

export def link [cfg: record] {
    [
        (shell-aliases vcs)
        # its bundled electron predates 38 and would run on scaled xwayland, unlike every other electron app here
        (desktop-exec github-desktop.desktop /usr/bin/github-desktop --args [--ozone-platform-hint=auto])
    ]
}
