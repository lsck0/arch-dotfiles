use module.nu *

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
        default: [print-applet geoclue-demo-agent remmina-applet app.fluxer.FluxerDesktop]
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

# program: the file whose presence means the tool is here; a link waits for it, so $HOME holds no link to a dir only
# home-dirs would make for a tool nobody installed. meta.inputs lists the column, so an install re-plans this module
const RECLAIM = [
    [name target mode program];
    # the install stage runs npm (obs, mason) before the session's environment.d exists; app-dirs.conf covers it after
    [.npm .cache/npm move /usr/bin/npm]
    # ANSIBLE_HOME in app-dirs.conf; a project's venv or devenv ansible made ~/.ansible before it
    [.ansible .local/share/ansible move /usr/bin/ansible]
    # DOTNET_CLI_HOME moves the sdk's dir, but the runtime's X509 store hardcodes ~/.dotnet/corefx
    [.dotnet .local/share/dotnet link /usr/bin/dotnet]
    # these honour CARGO_HOME, RUSTUP_HOME, ELAN_HOME, GHCUP_USE_XDG_DIRS and OPAMROOT, but the install stage runs them
    # before environment.d exists (as .npm), so a link covers every context instead of an app-dirs.conf line
    [.cargo .local/share/cargo link /usr/bin/cargo] [.rustup .local/share/rustup link /usr/bin/rustup]
    [.elan .local/share/elan link /usr/bin/elan] [.ghcup .local/share/ghcup link /usr/bin/ghcup]
    [.opam .local/share/opam link /usr/bin/opam]
    [.jai .local/share/jai link ~/.local/share/jai/bin/jai] [.kani .local/share/kani link /usr/bin/kani]
    [.nuget .local/share/nuget link /usr/bin/dotnet] [.mono .local/state/mono link /usr/bin/mono]
    [.subversion .config/subversion link /usr/bin/svn] [.cgdb .config/cgdb link /usr/bin/cgdb]
    [.android .local/share/android link ~/.local/share/android-sdk]
    [.mitmproxy .config/mitmproxy link /usr/bin/mitmproxy] [.proxychains .config/proxychains link /usr/bin/proxychains]
    [.msf4 .local/share/msf4 link /usr/bin/msfconsole] [.sliver .local/share/sliver link /usr/bin/sliver-server]
    [.sliver-client .local/share/sliver-client link /usr/bin/sliver-client] [.john .local/state/john link /usr/bin/john]
    [.tlaplus .local/share/tlaplus link /usr/bin/tla-toolbox]
    [.Macaulay2 .local/share/Macaulay2 link ~/.nix-profile/bin/M2] [.logseq .config/logseq link /usr/bin/logseq]
    [.zotero .local/share/zotero link /usr/bin/zotero]
    # Proton Pass writes its native messaging host into every browser's dir, librewolf's without librewolf
    [.librewolf .local/share/librewolf link /usr/bin/proton-pass] [.mozilla .local/share/mozilla link /usr/bin/firefox]
    [.zen .local/share/zen link /usr/bin/zen-browser]
    [.minecraft .local/share/minecraft link /usr/bin/minecraft-launcher]
    [.xlcore .local/share/xlcore link /usr/bin/xivlauncher-core] [.wine .local/share/wine link /usr/bin/wine]
    [.ZAP .local/share/ZAP link /usr/bin/zaproxy]
    # gtk reads ~/.themes and nss writes ~/.pki for whichever app links them
    [.themes .local/share/themes link /usr/lib/libgtk-3.so.0] [.pki .local/state/pki link /usr/lib/libnss3.so]
    [.task .local/state/task link /usr/bin/task] [.timewarrior .local/share/timewarrior link /usr/bin/timew]
    [.eclipse .local/share/eclipse link /usr/bin/eclipse] [.vscode-oss .local/share/vscode-oss link /usr/bin/codium]
    [.vscode-oss-shared .local/share/vscode-oss-shared link /usr/bin/codium]
    [.jd .local/share/jd link /usr/bin/jdownloader] [.nxc .local/share/nxc link /usr/bin/nxc]
    [.phoronix-test-suite .local/share/phoronix-test-suite link /usr/bin/phoronix-test-suite]
    [.renderdoc .local/state/renderdoc link /usr/bin/qrenderdoc] [.debug .local/state/debug link /usr/bin/perf]
    [.designer .local/state/designer link /usr/lib/qt6/bin/designer]
    [.epic .local/state/epic link ~/.local/share/unreal-engine] [.genius .config/genius link /usr/bin/genius]
    [.idlerc .config/idlerc link /usr/bin/idle3] [.kismet .local/state/kismet link /usr/bin/kismet]
    [.mcp-inspector .local/state/mcp-inspector link /usr/bin/npm]
    [.netscanner .local/state/netscanner link /usr/bin/netscanner] [.nnd .local/state/nnd link /usr/bin/nnd]
    [.superseedr .local/state/superseedr link /usr/bin/superseedr] [.usdview .local/state/usdview link /usr/bin/usdview]
    [.lyx .config/lyx link /usr/bin/lyx] [.java .config/java link /usr/bin/java]
    [.gemini .local/share/gemini link /usr/bin/gemini] [.copilot .local/share/copilot link /usr/bin/copilot]
    # copilot's skills dir, which the skills cli fills (programming/caveman)
    [.agents .local/share/agents link /usr/bin/copilot]
    [.caido-mcp .local/share/caido-mcp link /usr/bin/caido-mcp-server]
    [.lmmsrc.xml .config/lmms/lmmsrc.xml link-file /usr/bin/lmms]
    [.viminfo .local/state/vim/viminfo link-file /usr/bin/vim]
    [.wget-hsts .local/state/wget-hsts link-file /usr/bin/wget]
    [.indentconfig.yaml .config/latexindent/indentconfig.yaml link-file /usr/bin/latexindent]
]

# the applications dir's mtime: an entry added or removed there re-evaluates the desktop database's staleness
export const meta = {inputs: ([~/.local/share/applications] ++ $RECLAIM.program)}

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
    let links = $RECLAIM | where mode != move
        | where {|r| (reclaim-wanted $r) and (home $r.name | path type) not-in [dir file] }
    [
        (if not (home-dirs-done) { step home-dirs })
        (file-render config/mimeapps.list ($config | path join mimeapps.list) (mimeapps-values $cfg))
        (files-into $config config/user-dirs.conf config/user-dirs.dirs)
        (files-into ($config | path join environment.d) config/app-dirs.conf)
        (dropin xdg-document-portal.service services/doc-portal.conf --name 10-success-exit.conf)
        ($links | each {|r| file-link (reclaim-target $r) (home $r.name) })
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

def reclaim-wanted [r: record]: nothing -> bool {
    $r.program | path expand | path exists
}

# The dir a link reclaim needs in place: a link to nothing fails every mkdir through it, a tool's own and that of a
# file a module writes there.
def reclaim-parent [r: record]: nothing -> any {
    if not (reclaim-wanted $r) { return null }
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
