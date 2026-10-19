use module.nu *

export const meta = {packages: {pacman: [ghcup-hs-bin]}}

const GHCUP = "/usr/bin/ghcup"
const TOOLS = {ghc: ghc, cabal: cabal, hls: haskell-language-server-wrapper, stack: stack}

export def link [cfg: record] {
    if not ($GHCUP | path exists) { return [] }
    let bin = $env.GHCUP_INSTALL_BASE_PREFIX? | default $nu.home-dir | path join .ghcup bin
    $TOOLS | items {|tool, exe|
        let creates = $bin | path join $exe
        [
            (exec $"ghcup-install-($tool)" [$GHCUP install $tool] --creates $creates)
            (exec $"ghcup-set-($tool)" [$GHCUP set $tool] --creates $creates)
        ]
    } | flatten
}
