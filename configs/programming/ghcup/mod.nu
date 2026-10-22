use module.nu *

export const meta = {packages: {pacman: [ghcup-hs-bin]}}

const GHCUP = "/usr/bin/ghcup"
const TOOLS = {ghc: ghc, cabal: cabal, hls: haskell-language-server-wrapper, stack: stack}
# ghcup's own "recommended" version as of this writing, pinned so it stops floating; bump deliberately
const VERSIONS = {ghc: "9.10.3", cabal: "3.16.1.0", hls: "2.14.0.0", stack: "3.11.1"}

export def link [cfg: record] {
    if not ($GHCUP | path exists) { return [] }
    let bin = $env.GHCUP_INSTALL_BASE_PREFIX? | default $nu.home-dir | path join .ghcup bin
    $TOOLS | items {|tool, exe|
        let creates = $bin | path join $exe
        let version = $VERSIONS | get $tool
        [
            (exec $"ghcup-install-($tool)" [$GHCUP install $tool $version] --creates $creates)
            (exec $"ghcup-set-($tool)" [$GHCUP set $tool $version] --creates $creates)
        ]
    } | flatten
}
