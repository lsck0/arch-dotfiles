use module.nu *

export const meta = {
    packages: {
        pacman: [biber bibiman-bin lyx perl-file-homedir perl-yaml-tiny tectonic texlab texlive texlive-lang texmaker]
    }
}

const NAMES_DB = "luatex-cache/generic/names/luaotfload-names.lua.gz"

def texmf-var []: nothing -> path {
    $env.TEXMFVAR? | default (xdg cache texlive texmf-var)
}

export def link [cfg: record] {
    let var = texmf-var
    [
        (file-copy latexmkrc (xdg config latexmk latexmkrc))
        (if (which luaotfload-tool | is-empty) { [] } else {
            exec luaotfload-names [luaotfload-tool --update] --creates ($var | path join $NAMES_DB)
        })
    ]
}
