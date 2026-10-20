# per-machine app state moves to <dir>/<host>/<file> (module.nu host-file), so machines backing up into one repo stop
# overwriting each other's: credentials move (no seed, a new machine logs in itself), the rest is copied for a machine
# that runs the app and the shared copy stays as the seed a new machine starts from

use module.nu [host-file]
use secrets.nu [secret-is-plaintext secrets-wanted]

const REPO = path self ..

def repo []: nothing -> path { $env.DOTFILES? | default $REPO }

def home [...parts: string]: nothing -> path { $nu.home-dir | path join ...$parts }

# [shared, own, live]: own is this host's path; a seed is copied only where its app has live state here
def credentials []: nothing -> list<list<path>> {
    let secrets = repo | path join secrets
    [
        [($secrets | path join claude credentials.json) (host-file ($secrets | path join claude) credentials.json)]
        [($secrets | path join claude account.json) (host-file ($secrets | path join claude) account.json)]
        [($secrets | path join github) (host-file ($secrets | path join gh) token)]
    ]
}

def seeds []: nothing -> list<list<path>> {
    let secrets = repo | path join secrets
    let row = {|dir, file, live| [($dir | path join $file) (host-file $dir $file) $live] }
    let plasma = repo | path join configs desktop plasma
    let scenes = repo | path join configs creating obs scenes
    let applets = "plasma-org.kde.plasma.desktop-appletsrc"
    [
        (do $row $plasma $applets (home .config $applets))
        (do $row $scenes Bare.json (home .config obs-studio basic scenes Bare.json))
        (do $row $scenes VirtualCam.json (home .config obs-studio basic scenes VirtualCam.json))
        (do $row ($secrets | path join modrinth) app.db (home .local share ModrinthApp app.db))
        (do $row ($secrets | path join ffxiv) ffxivConfig (home .xlcore ffxivConfig FFXIV.cfg))
        (do $row ($secrets | path join ffxiv) launcher.ini (home .xlcore launcher.ini))
        (do $row ($secrets | path join dalamud) dalamudConfig.json (home .xlcore dalamudConfig.json))
        (do $row ($secrets | path join dalamud) dalamudUI.ini (home .xlcore dalamudUI.ini))
        (do $row ($secrets | path join dalamud) pluginConfigs (home .xlcore pluginConfigs))
    ]
}

# writing into a locked secrets/ would stage plaintext into blob paths; a machine without secrets has none to move
def secrets-ready []: nothing -> bool {
    if not (secrets-wanted) or not (repo | path join secrets | path exists) { return false }
    if not (secret-is-plaintext (repo | path join secrets pgp_privatekey.asc)) {
        error make {msg: "secrets is locked, unlock it (dot secrets unlock) and run dot sync again"}
    }
    true
}

def in-secrets [p: path]: nothing -> bool { $p | str starts-with (repo | path join secrets) }

export def up []: nothing -> nothing {
    let ready = secrets-ready
    for c in (credentials) {
        if not $ready or not ($c.0 | path exists) or ($c.1 | path exists) { continue }
        mkdir ($c.1 | path dirname)
        mv $c.0 $c.1
    }
    for s in (seeds) {
        if ((in-secrets $s.0) and not $ready) or not ($s.0 | path exists) or ($s.1 | path exists) { continue }
        if not ($s.2 | path exists) { continue }
        mkdir ($s.1 | path dirname)
        ^cp -a $s.0 $s.1
    }
}

# this host's copy back to the shared path; a seed is replaced by it, the newest state this machine had
export def down []: nothing -> nothing {
    let ready = secrets-ready
    for c in ((credentials) ++ (seeds)) {
        if ((in-secrets $c.0) and not $ready) or not ($c.1 | path exists) { continue }
        rm --recursive --force $c.0
        mv $c.1 $c.0
        let dir = $c.1 | path dirname
        if (ls --all $dir | is-empty) { rm $dir }
    }
}
