use module.nu *

export const meta = {
    packages: {
        pacman: [
            difftastic git-absorb git-age git-filter-repo git-lfs github-cli jujutsu lazyjj mergiraf onefetch
            pre-commit tig
        ]
    }
}

export def link [cfg: record] {
    shell-aliases vcs
}
