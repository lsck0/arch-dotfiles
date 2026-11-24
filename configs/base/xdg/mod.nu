use module.nu *

# the applications dir's mtime: an entry added or removed there re-evaluates the desktop database's staleness
export const meta = {inputs: [~/.local/share/applications]}

export const options = {
    browser: {
        type: list<string>
        default: [firefox.desktop]
        doc: "Desktop entries for web pages and links, first wins"
        label: "Browser"
        group: apps
        scope: user
    }
    editor: {
        type: list<string>
        default: [neovide.desktop nvim.desktop org.gnome.TextEditor.desktop]
        doc: "Desktop entries for text, source and config files, first wins"
        label: "Text editor"
        group: apps
        scope: user
    }
    file_manager: {
        type: list<string>
        default: [org.kde.dolphin.desktop nemo.desktop]
        doc: "Desktop entries for folders, first wins"
        label: "File manager"
        group: apps
        scope: user
    }
    pdf_viewer: {
        type: list<string>
        default: [org.kde.okular.desktop org.pwmt.zathura.desktop]
        doc: "Desktop entries for PDFs, first wins"
        label: "PDF viewer"
        group: apps
        scope: user
    }
    image_viewer: {
        type: list<string>
        default: [feh.desktop nsxiv.desktop]
        doc: "Desktop entries for images, first wins (raw photos stay with rawtherapee)"
        label: "Image viewer"
        group: apps
        scope: user
    }
    media_player: {
        type: list<string>
        default: [mpv.desktop]
        doc: "Desktop entries for audio and video, first wins"
        label: "Media player"
        group: apps
        scope: user
    }
    autostart_hidden: {
        type: list<string>
        default: [print-applet geoclue-demo-agent remmina-applet]
        doc: "XDG autostart entries hidden from the session, by desktop file id"
        label: "Hidden autostart entries"
        scope: user
    }
}

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
    $kept ++ $missing | to text | save --force $PAM_ENV
}

const DIRS = [desktop documents downloads music pictures videos sync vault .local/share/applications]
const CAPITALIZED = [Desktop Documents Downloads Music Pictures Projects Public Templates Videos]
const USER_DIRS = path self config/user-dirs.dirs
const PLASMA_MENU = "/etc/xdg/menus/plasma-applications.menu"

# A dir user-dirs.dirs names (DOCUMENTS, VIDEOS, ...), read from the repo: xdg-user-dir answers $HOME until this
# module's copy lands, and a fresh install's first run plans every module before it applies any.
export def user-dir [name: string]: nothing -> path {
    let pattern = '^XDG_' + $name + '_DIR="\$HOME/(?<dir>.*)"$'
    let dir = open --raw $USER_DIRS | lines | parse --regex $pattern | get --optional 0.dir
    if $dir == null { error make {msg: $"xdg: user-dirs.dirs names no XDG_($name)_DIR under $HOME"} }
    $nu.home-dir | path join $dir
}

const RECLAIM = [
    [name target mode];
    # the install stage runs npm (obs, mason) before the session's environment.d exists; app-dirs.conf covers it after
    [.npm .cache/npm move]
    # ANSIBLE_HOME in app-dirs.conf; a project's venv or devenv ansible made ~/.ansible before it
    [.ansible .local/share/ansible move]
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

# update-desktop-database renames its cache into the dir, so the dir's mtime trails the cache's by under a millisecond
const DESKTOP_CACHE_SLACK = 1sec

const XBEL_NS = "http://www.freedesktop.org/standards/desktop-bookmarks"
const XBEL_END = "</xbel>"

def home [...parts: string]: nothing -> path {
    $nu.home-dir | path join ...$parts
}

# The places panel's marks; gtk: also a gtk-3.0 sidebar bookmark, which for gtk's built-in xdg dirs is only their label:
# it names those by their (lowercase) directory otherwise. Desktop is no built-in there, so a bookmark would double it
def places [nas: bool, projects: bool]: nothing -> list<record> {
    let h = $"file://($nu.home-dir)"
    let rows = [
        [href title icon gtk shown];
        [$h Home user-home false true] [$"($h)/desktop" Desktop user-desktop false true]
        [$"($h)/documents" Documents folder-documents true true] [$"($h)/downloads" Downloads folder-downloads true true]
        [$"($h)/music" Music folder-music true true] [$"($h)/pictures" Pictures folder-pictures true true]
        [$"($h)/videos" Videos folder-videos true true] [$"($h)/projects" Projects folder-development true $projects]
        [$"($h)/vault" Vault folder-locked true true] [$"($h)/sync" Sync folder-sync true true]
        [$"($h)/nas" NAS folder-network true $nas] [trash:/ Trash user-trash false true]
    ]
    $rows | where shown | each {|r|
        let icon = $'<metadata owner="http://freedesktop.org"><bookmark:icon name="($r.icon)" /></metadata>'
        let system = '<metadata owner="http://www.kde.org"><isSystemItem>true</isSystemItem></metadata>'
        $r | insert xml $'<bookmark href="($r.href)"><title>($r.title)</title><info>($icon)($system)</info></bookmark>'
    }
}

# The live places file (kio rewrites it on every change) plus any missing mark, so an apply writes only if one is gone.
def places-xbel [file: path, marks: list<record>]: nothing -> string {
    let live = if ($file | path exists) { open --raw $file } else { "" }
    if not ($live | str contains $XBEL_END) {
        let head = $"<?xml version='1.0' encoding='UTF-8'?>\n<xbel xmlns:bookmark=\"($XBEL_NS)\">"
        return $"($head)($marks.xml | str join)($XBEL_END)"
    }
    let missing = $marks | where {|m| not ($live | str contains $'href="($m.href)"') }
    if ($missing | is-empty) { return $live }
    $live | str replace $XBEL_END $"($missing.xml | str join)($XBEL_END)"
}

# mimeapps.list's value for desktop entries: each followed by a semicolon
def mime-entries [entries: list<string>]: nothing -> string {
    $entries | each { $"($in);" } | str join
}

def mimeapps-values [cfg: record]: nothing -> record {
    {
        BROWSER: (mime-entries $cfg.browser), EDITOR: (mime-entries $cfg.editor)
        FILE_MANAGER: (mime-entries $cfg.file_manager), FILE_MANAGER_FIRST: (mime-entries ($cfg.file_manager | first 1))
        PDF_VIEWER: (mime-entries $cfg.pdf_viewer), PDF_VIEWER_FIRST: (mime-entries ($cfg.pdf_viewer | first 1))
        IMAGE_VIEWER: (mime-entries $cfg.image_viewer), MEDIA_PLAYER: (mime-entries $cfg.media_player)
    }
}

export def link [cfg: record] {
    let config = xdg config
    # core/nas makes ~/nas only for an unlocked owner, so the bookmark follows the same gate
    let nas = (owner-unlocked) and (platform-has homelab)
    let projects = home projects | path exists
    let portals = $config | path join xdg-desktop-portal
    let places = places $nas $projects
    let bookmarks = $places | where gtk | each { $"($in.href) ($in.title)" }
    let xbel = xdg data user-places.xbel
    [
        (if not (home-dirs-done) { step home-dirs })
        (file-render config/mimeapps.list ($config | path join mimeapps.list) (mimeapps-values $cfg))
        (files-into $config config/user-dirs.conf config/user-dirs.dirs)
        (files-into ($config | path join environment.d) config/app-dirs.conf)
        (dropin xdg-document-portal.service services/doc-portal.conf --name 10-success-exit.conf)
        ($RECLAIM | where mode != move and ((home $it.name | path type) not-in [dir file]) | each {|r|
            file-link (reclaim-target $r) (home $r.name)
        })
        (file-copy config/home.hidden (home .hidden))
        ($cfg.autostart_hidden | each {|id|
            let entry = $"[Desktop Entry]\nType=Application\nName=($id)\nHidden=true\n"
            file-text ($config | path join autostart $"($id).desktop") $entry
        })
        (if (which Hyprland | is-not-empty) {[
            # the portal reads its routing only at start
            (file-copy config/hyprland-portals.conf ($portals | path join hyprland-portals.conf)
                --then (unit-restart xdg-desktop-portal.service --if-running))
            # kde's open-with dialog and every kservice menu read $XDG_MENU_PREFIX applications.menu, which uwsm
            # names after the compositor; plasma's file is the one with categories, and ksycoca rebuilds when the dir
            # changes
            (if ($PLASMA_MENU | path exists) { files-into ($config | path join menus) config/hyprland-applications.menu })
        ]})
        # a user kde-portals.conf replaces plasma's whole file, so it repeats plasma's lines
        (if (which startplasma-wayland | is-not-empty) { files-into $portals config/kde-portals.conf })
        (file-text ($config | path join gtk-3.0 bookmarks) ($bookmarks | to text))
        (file-text $xbel (places-xbel $xbel $places) --generated)
        (if (which update-desktop-database | is-not-empty) and (desktop-database-stale) {
            exec "desktop database" [update-desktop-database (xdg data applications)]
        })
    ]
}

# Whether an entry under applications/ changed since update-desktop-database last wrote mimeinfo.cache.
def desktop-database-stale []: nothing -> bool {
    let dir = xdg data applications
    let cache = $dir | path join mimeinfo.cache
    if not ($cache | path exists) { return true }
    let built = (ls --long $cache | get 0.modified) + $DESKTOP_CACHE_SLACK
    let entries = glob ($dir | path join "**" "*") | where $it != $cache | append $dir
    $entries | any {|e| (ls --long --directory $e | get 0.modified) > $built }
}

def reclaim-target [r: record]: nothing -> path {
    # a cache target follows XDG_CACHE_HOME, as app-dirs.conf's npm_config_cache does
    if ($r.target | str starts-with .cache/) {
        xdg cache ($r.target | str replace --regex '^\.cache/' '')
    } else {
        home $r.target
    }
}

# The dir a link reclaim needs in place: a link to nothing fails every mkdir through it, a tool's own and that of a
# file a module writes there.
def reclaim-parent [r: record]: nothing -> any {
    let target = reclaim-target $r
    match $r.mode { "link" => $target, "link-file" => ($target | path dirname), _ => null }
}

# Whether home-dirs has nothing left to do; a reclaim whose target already exists waits for a manual merge.
def home-dirs-done []: nothing -> bool {
    let capitalized = $CAPITALIZED | each { home $in } | where { ($in | path type) == dir and (ls --all $in | is-empty) }
    let reclaim = $RECLAIM | where {|r|
        let target = reclaim-target $r
        let movable = ((home $r.name) | path type) in [dir file] and not ($target | path exists)
        let parent = reclaim-parent $r
        $movable or ($parent != null and ($parent | path type) != dir)
    }
    ($DIRS | all { (home $in | path type) == dir }) and ($capitalized | is-empty) and ($reclaim | is-empty)
}

export def home-dirs []: nothing -> nothing {
    mkdir ...($DIRS | each { home $in })
    for dir in $CAPITALIZED { ^rmdir (home $dir) | complete | ignore }
    for r in $RECLAIM {
        let src = home $r.name
        let target = reclaim-target $r
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
        let parent = reclaim-parent $r
        if $parent != null { mkdir $parent }
    }
}
