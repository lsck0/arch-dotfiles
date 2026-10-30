use module.nu *

const PAM_ENV = "/etc/security/pam_env.conf"
# app-dirs.conf's environment.d reaches only the graphical session; ssh and tty logins get these, or go creates ~/go
const PAM_LINES = [
    "XDG_CONFIG_HOME DEFAULT=@{HOME}/.config" "XDG_CACHE_HOME  DEFAULT=@{HOME}/.cache"
    "XDG_DATA_HOME   DEFAULT=@{HOME}/.local/share" "XDG_STATE_HOME  DEFAULT=@{HOME}/.local/state"
    "GOPATH          DEFAULT=@{HOME}/.local/share/go"
]

export def system [cfg: record] {
    step pam-env
}

# Replaces any other line for a variable it sets, so a changed value never leaves the old one ahead of it.
export def pam-env []: nothing -> nothing {
    let names = $PAM_LINES | each { split row " " | first }
    let have = open --raw $PAM_ENV | lines
    let kept = $have | where {|l| $l in $PAM_LINES or ($l | split row --regex '\s+' | first) not-in $names }
    let missing = $PAM_LINES | where $it not-in $kept
    if ($missing | is-empty) and ($kept | length) == ($have | length) { return }
    $kept ++ $missing | str join "\n" | $"($in)\n" | save --force $PAM_ENV
}

const DIRS = [desktop documents downloads music pictures videos sync vault]
const CAPITALIZED = [Desktop Documents Downloads Music Pictures Projects Public Templates Videos]

const RECLAIM = [
    [name target mode];
    # the install stage runs npm (obs, mason) before the session's environment.d exists; app-dirs.conf covers it after
    [.npm .cache/npm move]
    # DOTNET_CLI_HOME moves the sdk's dir, but the runtime's X509 store hardcodes ~/.dotnet/corefx
    [.dotnet .local/share/dotnet link]
    # these honour CARGO_HOME, RUSTUP_HOME, ELAN_HOME, GHCUP_USE_XDG_DIRS and OPAMROOT, but the install stage runs them
    # before environment.d exists (as .npm), so a link covers every context instead of an app-dirs.conf line
    [.cargo .local/share/cargo link] [.rustup .local/share/rustup link] [.elan .local/share/elan link]
    [.ghcup .local/share/ghcup link] [.opam .local/share/opam link]
    [.jai .local/share/jai link] [.kani .local/share/kani link] [.nuget .local/share/nuget link]
    [.mono .local/state/mono link] [.subversion .config/subversion link] [.cgdb .config/cgdb link]
    [.android .local/share/android link]
    [.mitmproxy .config/mitmproxy link] [.proxychains .config/proxychains link] [.msf4 .local/share/msf4 link]
    [.sliver .local/share/sliver link] [.sliver-client .local/share/sliver-client link] [.john .local/state/john link]
    [.tlaplus .local/share/tlaplus link] [.Macaulay2 .local/share/Macaulay2 link] [.logseq .config/logseq link]
    [.zotero .local/share/zotero link] [.librewolf .local/share/librewolf link] [.mozilla .local/share/mozilla link]
    [.zen .local/share/zen link] [.minecraft .local/share/minecraft link] [.xlcore .local/share/xlcore link]
    [.wine .local/share/wine link] [.ZAP .local/share/ZAP link] [.themes .local/share/themes link]
    [.task .local/state/task link] [.timewarrior .local/share/timewarrior link] [.pki .local/state/pki link]
    [.eclipse .local/share/eclipse link] [.vscode-oss .local/share/vscode-oss link]
    [.vscode-oss-shared .local/share/vscode-oss-shared link] [.jd .local/share/jd link] [.nxc .local/share/nxc link]
    [.phoronix-test-suite .local/share/phoronix-test-suite link] [.renderdoc .local/state/renderdoc link]
    [.debug .local/state/debug link] [.designer .local/state/designer link] [.epic .local/state/epic link]
    [.genius .config/genius link] [.idlerc .config/idlerc link] [.kismet .local/state/kismet link]
    [.mcp-inspector .local/state/mcp-inspector link] [.netscanner .local/state/netscanner link]
    [.nnd .local/state/nnd link] [.superseedr .local/state/superseedr link] [.usdview .local/state/usdview link]
    [.lyx .config/lyx link] [.java .config/java link]
    [.gemini .local/share/gemini link] [.copilot .local/share/copilot link] [.agents .local/share/agents link]
    [.caido-mcp .local/share/caido-mcp link]
    [.lmmsrc.xml .config/lmms/lmmsrc.xml link-file]
    [.viminfo .local/state/vim/viminfo link-file]
    [.wget-hsts .local/state/wget-hsts link-file] [.indentconfig.yaml .config/latexindent/indentconfig.yaml link-file]
]

const XBEL_NS = "http://www.freedesktop.org/standards/desktop-bookmarks"
const XBEL_END = "</xbel>"

def home [...parts: string]: nothing -> path {
    $nu.home-dir | path join ...$parts
}

def places [nas: bool, projects: bool]: nothing -> list<record> {
    let h = $"file://($nu.home-dir)"
    let rows = [
        [$h Home user-home] [$"($h)/desktop" Desktop user-desktop] [$"($h)/documents" Documents folder-documents]
        [$"($h)/downloads" Downloads folder-downloads] [$"($h)/music" Music folder-music]
        [$"($h)/pictures" Pictures folder-pictures] [$"($h)/videos" Videos folder-videos]
    ] ++ (if $projects { [[$"($h)/projects" Projects folder-development]] } else { [] }) ++ [
        [$"($h)/vault" Vault folder-locked] [$"($h)/sync" Sync folder-sync]
    ] ++ (if $nas { [[$"($h)/nas" NAS folder-network]] } else { [] }) ++ [[trash:/ Trash user-trash]]
    $rows | each {|r|
        let icon = $'<metadata owner="http://freedesktop.org"><bookmark:icon name="($r.2)" /></metadata>'
        let system = '<metadata owner="http://www.kde.org"><isSystemItem>true</isSystemItem></metadata>'
        {href: $r.0, xml: $'<bookmark href="($r.0)"><title>($r.1)</title><info>($icon)($system)</info></bookmark>'}
    }
}

# The live places file (kio rewrites it on every change) plus any missing mark, so an apply writes only if one is gone.
def places-xbel [marks: list<record>]: nothing -> string {
    let file = home .local share user-places.xbel
    let live = if ($file | path exists) { open --raw $file } else { "" }
    if not ($live | str contains $XBEL_END) {
        let head = $"<?xml version='1.0' encoding='UTF-8'?>\n<xbel xmlns:bookmark=\"($XBEL_NS)\">"
        return $"($head)($marks.xml | str join)($XBEL_END)"
    }
    let missing = $marks | where {|m| not ($live | str contains $'href="($m.href)"') }
    if ($missing | is-empty) { return $live }
    $live | str replace $XBEL_END $"($missing.xml | str join)($XBEL_END)"
}

def autostart-hidden []: nothing -> list<string> {
    open --raw hidden-autostart.list | lines | each { split row "#" | first | str trim } | where $it != ""
}

export def link [cfg: record] {
    let config = home .config
    # core/nas makes ~/nas only for an unlocked owner, so the bookmark follows the same gate
    let nas = (owner-unlocked) and (platform-has homelab)
    let projects = home projects | path exists
    let portals = $config | path join xdg-desktop-portal
    let marks = (if $projects { [[projects Projects]] } else { [] }) ++ [[vault Vault] [sync Sync]]
    let bookmarks = $marks ++ (if $nas { [[nas NAS]] } else { [] }) | each { $"file://(home $in.0) ($in.1)" }
    [
        (step home-dirs)
        (files-into $config mimeapps.list user-dirs.conf user-dirs.dirs)
        (files-into ($config | path join environment.d) app-dirs.conf)
        (dropin xdg-document-portal.service doc-portal.conf --name 10-success-exit.conf)
        ($RECLAIM | where mode != move and ((home $it.name | path type) not-in [dir file]) | each {|r|
            file-link (home $r.target) (home $r.name)
        })
        # nemo also claims FileManager1 and sorts first; the user dir wins, so only where dolphin exists
        (if ("/usr/bin/dolphin" | path exists) {
            let service = home .local share dbus-1 services org.freedesktop.FileManager1.service
            file-copy dolphin.FileManager1.service $service
        } else { [] })
        (file-copy home.hidden (home .hidden))
        (autostart-hidden | each {|id|
            let entry = $"[Desktop Entry]\nType=Application\nName=($id)\nHidden=true\n"
            file-text ($config | path join autostart $"($id).desktop") $entry
        })
        # a user kde-portals.conf replaces plasma's whole file, so it repeats plasma's lines
        (if (which Hyprland | is-not-empty) { files-into $portals hyprland-portals.conf } else { [] })
        (if (which startplasma-wayland | is-not-empty) { files-into $portals kde-portals.conf } else { [] })
        (file-text ($config | path join gtk-3.0 bookmarks) ($bookmarks | str join "\n" | $"($in)\n"))
        (file-text (home .local share user-places.xbel) (places-xbel (places $nas $projects)) --generated)
        (if (which update-desktop-database | is-not-empty) {
            exec "desktop database" [update-desktop-database (home .local share applications)]
        } else { [] })
    ] | decls-flatten
}

export def home-dirs []: nothing -> nothing {
    mkdir ...($DIRS | each { home $in }) (home .local share applications)
    for dir in $CAPITALIZED { ^rmdir (home $dir) | complete | ignore }
    for r in $RECLAIM {
        let src = home $r.name
        # a cache target follows XDG_CACHE_HOME, as app-dirs.conf's npm_config_cache does
        let target = if ($r.target | str starts-with .cache/) {
            xdg cache ($r.target | str replace --regex '^\.cache/' '')
        } else {
            home $r.target
        }
        if ($src | path type) in [dir file] {
            if ($target | path exists) {
                print $"note: xdg: ($r.name): ($target) exists, left ($src) for a manual merge"
                continue
            }
            mkdir ($target | path dirname)
            mv $src $target
            if $r.mode != move { ^ln -s $target $src }
            print $"xdg: moved ($src) -> ($target)"
        }
        # a link to nothing fails every mkdir through it: a tool's own, and that of a file a module writes there
        match $r.mode { "link" => { mkdir $target }, "link-file" => { mkdir ($target | path dirname) }, _ => {} }
    }
}
