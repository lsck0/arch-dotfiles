use module.nu *

export const meta = {
    packages: {
        pacman: [biber bibiman-bin lyx perl-file-homedir perl-yaml-tiny tectonic texlab texlive texlive-lang texmaker]
    }
}

const NAMES_DB = "luatex-cache/generic/names/luaotfload-names.lua.gz"

def texmf-var []: nothing -> path {
    $env.TEXMFVAR? | default ($env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join texlive texmf-var)
}

export def link [cfg: record] {
    let var = texmf-var
    [
        (file-copy latexmkrc ($nu.home-dir | path join .config latexmk latexmkrc))
        (if (which luaotfload-tool | is-empty) { [] } else {
            exec luaotfload-names [env $"TEXMFVAR=($var)" luaotfload-tool --update] --creates ($var | path join $NAMES_DB)
        })
    ]
}
