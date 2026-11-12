use module.nu *

export const meta = {
    packages: {
        pacman: [biber bibiman-bin lyx perl-file-homedir perl-yaml-tiny tectonic texlab texlive texlive-lang texmaker]
    }
}

const NAMES_DB = "luatex-cache/generic/names/luaotfload-names.lua.gz"

export def link [cfg: record] {
    let names = $env.TEXMFVAR? | default (xdg cache texlive texmf-var) | path join $NAMES_DB
    [
        (file-copy latexmkrc (xdg config latexmk latexmkrc))
        (if (which luaotfload-tool | is-not-empty) {
            exec luaotfload-names [luaotfload-tool --update] --creates $names
        })
    ]
}
