use module.nu *

export const meta = {packages: {pacman: [ghcup-hs-bin]}}

const GHCUP = "/usr/bin/ghcup"
# ghcup's own "recommended" version as of this writing, pinned so it stops floating; bump deliberately
const TOOLS = [
    [tool exe version];
    [ghc ghc "9.10.3"]
    [cabal cabal "3.16.1.0"]
    [hls haskell-language-server-wrapper "2.14.0.0"]
    [stack stack "3.11.1"]
]

export def link [cfg: record] {
    if not ($GHCUP | path exists) { return [] }
    let bin = $env.GHCUP_INSTALL_BASE_PREFIX? | default $nu.home-dir | path join .ghcup bin
    $TOOLS | each {|t|
        # versioned marker: a version bump has no matching file yet, so the install runs
        let installed = $bin | path join $"($t.exe)-($t.version)"
        # set runs unless the unversioned link already resolves to this version
        let active_matches = $bin | path join $t.exe | path expand | str contains $t.version
        [
            # named by its version: a bump orphans the old install, whose undo removes only that pinned version
            (exec $"ghcup-install-($t.tool) ($t.version)" [$GHCUP install $t.tool $t.version] --creates $installed
                --undo [$GHCUP rm $t.tool $t.version] --network)
            # set reads ghcup's metadata over the network, and only after the install landed
            (exec $"ghcup-set-($t.tool)" [$GHCUP set $t.tool $t.version] --done=$active_matches --requires $installed --network)
        ]
    }
}
