use module.nu *
use ../../core/nas/scripts/vendor.nu [nas-vendor-dir nas-vendor-newer nas-vendor-newest]

# volatile: a newer engine zip on the NAS is no local input
export const meta = {packages: {pacman: [libnotify shared-mime-info unzip]}, volatile: true}

const ZIP_GLOB = "Linux_Unreal_Engine_*.zip"
const STAMP = ".installed-from"
const EDITOR = "Engine/Binaries/Linux/UnrealEditor"
const ICON = "Engine/Source/Runtime/Launch/Resources/Linux/UnrealEngine.png"
const CANARY = '^[^\]\[*?]*/Private/[^\]\[*?/]+$'
const PLUGINS_INSTALL = path self scripts/unreal-install-plugins.nu
# the engine zip unpacks to ~60 GB
const INSTALL_TIMEOUT = 60min
const FREE_MIN_PERCENT = 15
# the editor's MCP server, on unreal-editor.nu's MCP_PORT
const MCP_ADDRESS = "127.0.0.1:8766"
const MCP = {type: http, url: $"http://($MCP_ADDRESS)/mcp", gate: {probe: $MCP_ADDRESS, app: "the Unreal editor"}}

def engine-dir []: nothing -> path { xdg data unreal-engine }

def zip-version [name: string]: nothing -> string {
    $name | str replace --regex '\.zip$' '' | str replace 'Linux_Unreal_Engine_' ''
}

def desktop-text [version: string]: nothing -> string {
    let icon = engine-dir | path join $ICON
    [
        "[Desktop Entry]" "Type=Application" "Name=Unreal Engine" $"Comment=Unreal Editor ($version)"
        "# the launcher (unreal-editor.nu) starts the mcp server"
        $"Exec=($nu.home-dir | path join .local bin unreal-editor) %U"
        (if ($icon | path exists) { $"Icon=($icon)" })
        "Terminal=false" "Categories=Development;IDE;" "MimeType=application/x-uproject;" "StartupWMClass=UnrealEditor"
    ] | compact | to text
}

# Drops the half-unpacked staging dir and exits 1.
def fail [staging: path, message: string]: nothing -> nothing {
    rm --recursive --force $staging
    print -e $"unreal: ($message)"
    exit 1
}

# Unpacks zip into a staging dir beside the engine and swaps it in once whole; never runs anything off the share.
export def unreal-install [zip: string]: nothing -> nothing {
    let name = $zip | path basename
    let engine = engine-dir
    let installed = $engine | path join $STAMP | path exists
    # not /tmp: ~60 GB and /tmp is tmpfs; the old engine goes only once the new one is whole
    let staging = $"($engine).new"
    rm --recursive --force $staging
    mkdir $staging
    let unpacked = ^unzip -Zt $zip | parse --regex '(?<bytes>\d+) bytes uncompressed' | get 0.bytes | into int
    let disk = ^df --output=avail,size --block-size=1 $staging | lines | last | str trim | split row --regex '\s+' | into int
    if $disk.0 - $unpacked < $disk.1 * $FREE_MIN_PERCENT // 100 {
        fail $staging $"($name) unpacks to ($unpacked | into filesize), which would leave less than ($FREE_MIN_PERCENT)% of the disk free"
    }
    # unzip fails only after tens of GB, and apparmor's deny-sensitive-home refuses every Private dir
    let canary = ^zipinfo -1 $zip | lines | where $it =~ $CANARY | get --optional 0
    if $canary != null {
        if (^unzip -q $zip $canary -d $staging | complete).exit_code != 0 {
            fail $staging $"cannot unpack ($canary) into ($staging), check the unzip apparmor profile"
        }
        rm --recursive --force $staging
        mkdir $staging
    }
    if (^unzip -q $zip -d $staging | complete).exit_code != 0 {
        fail $staging $"cannot unpack ($name) into ($staging)"
    }
    let root = [$staging] ++ (ls $staging | where type == dir | get name)
        | where {|d| ($d | path join Engine | path type) == dir } | get --optional 0
    if $root == null or not ($root | path join $EDITOR | path exists) {
        fail $staging $"no ($EDITOR) in ($name)"
    }
    $"($name)\n" | save --force ($root | path join $STAMP)
    if ($engine | path exists) and not $installed {
        mv $engine $"($engine).pre-dotfiles-(date now | format date '%Y%m%d%H%M%S')"
        print -e $"unreal: kept the existing ($engine) aside"
    }
    rm --recursive --force $engine
    mv $root $engine
    rm --recursive --force $staging
    try { ^$PLUGINS_INSTALL } catch { print -e "unreal: plugins not installed, rerun unreal-install-plugins" }
    ^notify-send -a unreal "Unreal Engine installed" $"Version (zip-version $name) in ($engine)" | complete | ignore
}

export def link [cfg: record] {
    if $env.FORM_FACTOR? != "desktop" { return [] }
    let mime = xdg data mime
    let stamp = engine-dir | path join $STAMP
    let installed = file-trim $stamp
    let vendor = nas-vendor-dir
    let zip = nas-vendor-newest $vendor $ZIP_GLOB
    let name = if $zip == null { "" } else { $zip | path basename }
    let newer = nas-vendor-newer $installed $name
    if $vendor == null {
        log-note $"unreal: the NAS vendor dir is not reachable, (if $installed == '' { 'no engine installed' } else { $'keeping ($installed)' })"
    }
    [
        (link-commands scripts/unreal-editor.nu scripts/unreal-install-plugins.nu)
        (file-copy config/uproject.xml ($mime | path join packages uproject.xml) --then [update-mime-database $mime])
        (mcp-servers {unreal-mcp: (if $installed != "" { $MCP })})
        (if $newer { step unreal-install $zip --key $name --creates $stamp --timeout $INSTALL_TIMEOUT })
        # base/xdg refreshes the desktop database
        (if $installed != "" { file-text (xdg data applications unreal-engine.desktop) (desktop-text (zip-version $installed)) })
    ]
}
