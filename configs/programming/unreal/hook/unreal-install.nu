#!/usr/bin/env -S nu --no-config-file
# the engine from the newest ~/sync/vendor zip (Epic-login-gated, synced from where it was downloaded), into the home
# like jai: part of the dotfiles, so never asked and never root. no-op unless the zip is new; mod.nu reruns it for later
# versions

const PLUGINS_INSTALL = path self | path expand | path dirname --num-levels 2 | path join unreal-install-plugins.nu
const ZIP_GLOB = "Linux_Unreal_Engine_*.zip"
const EDITOR = "Engine/Binaries/Linux/UnrealEditor"
const ICON = "Engine/Source/Runtime/Launch/Resources/Linux/UnrealEngine.png"
# a file under a Private dir, without the characters unzip reads as a pattern
const CANARY = '^[^\]\[*?]*/Private/[^\]\[*?/]+$'

def data-dir []: nothing -> path { $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) }

def engine-dir []: nothing -> path { data-dir | path join unreal-engine }

def zip-newest []: nothing -> any {
    glob ($nu.home-dir | path join sync vendor $ZIP_GLOB) | sort --natural | last
}

# rewritten on every run, not only on an install, so a fix here reaches an engine that is already in
def desktop-write [version: string]: nothing -> nothing {
    let file = data-dir | path join applications unreal-engine.desktop
    # the binary zip ships no UnrealVersionSelector sources, only the launch module's own linux icon
    let icon = engine-dir | path join $ICON
    mkdir ($file | path dirname)
    [
        "[Desktop Entry]" "Type=Application" "Name=Unreal Engine" $"Comment=Unreal Editor ($version)"
        "# the launcher (mod.nu) adds the mcp server"
        $"Exec=($nu.home-dir | path join .local bin unreal-editor) %U"
        (if ($icon | path exists) { $"Icon=($icon)" })
        "Terminal=false" "Categories=Development;IDE;" "MimeType=application/x-uproject;" "StartupWMClass=UnrealEditor"
    ] | compact | str join "\n" | $"($in)\n" | save --force $file
    if (which update-desktop-database | is-not-empty) {
        ^update-desktop-database ($file | path dirname) | complete | ignore
    }
}

def fail [message: string]: nothing -> nothing {
    print -e $"unreal: ($message)"
    exit 1
}

def main []: nothing -> nothing {
    if (zip-newest) == null { return }
    mkdir (data-dir)
    # dot link and the path unit both run this: the second waits, then finds the stamp the first wrote
    ^flock $"(engine-dir).lock" $nu.current-exe --no-config-file $env.CURRENT_FILE locked
}

def "main locked" []: nothing -> nothing {
    let zip = zip-newest
    let name = $zip | path basename
    let version = $name | str replace --regex '\.zip$' '' | str replace 'Linux_Unreal_Engine_' ''
    let engine = engine-dir
    let stamp = $engine | path join .installed-from
    let installed = $stamp | path exists
    if $installed and (open --raw $stamp | str trim) == $name {
        desktop-write $version
        return
    }
    # unpacked next to the engine, not in /tmp: ~60 GB, and /tmp is tmpfs; the old engine only goes once the new one
    # is whole
    let staging = $"($engine).new"
    rm --recursive --force $staging
    mkdir $staging
    # one file under a Private dir first: unzip only fails at the end, after minutes and tens of GB, and the path unit
    # retriggers it, so a confinement that refuses the tree (deny-sensitive-home denies every Private dir) fails here in
    # seconds instead
    let canary = ^zipinfo -1 $zip | lines | where $it =~ $CANARY | get --optional 0
    if $canary != null {
        if (^unzip -q $zip $canary -d $staging | complete).exit_code != 0 {
            rm --recursive --force $staging
            fail $"cannot unpack ($canary) into ($staging), check the unzip apparmor profile"
        }
        rm --recursive --force $staging
        mkdir $staging
    }
    if (^unzip -q $zip -d $staging | complete).exit_code != 0 {
        rm --recursive --force $staging
        fail $"cannot unpack ($name) into ($staging)"
    }
    # the zip holds Engine/ either at its top or under one folder
    let root = [$staging] ++ (ls $staging | where type == dir | get name)
        | where {|d| ($d | path join Engine | path type) == dir } | get --optional 0
    if $root == null or not ($root | path join $EDITOR | path exists) {
        rm --recursive --force $staging
        fail $"no ($EDITOR) in ($name)"
    }
    $"($name)\n" | save --force ($root | path join .installed-from)
    # an engine dir without the stamp is not one this hook installed: kept aside (a rename, same filesystem), never
    # deleted
    if ($engine | path exists) and not $installed {
        mv $engine $"($engine).pre-dotfiles-(date now | format date '%Y%m%d%H%M%S')"
        print -e $"unreal: kept the existing ($engine) aside"
    }
    rm --recursive --force $engine
    mv $root $engine
    rm --recursive --force $staging
    desktop-write $version
    # bridge and fab from ~/sync/vendor go into the engine, which is the user's own now
    try { ^$PLUGINS_INSTALL } catch { print -e "unreal: plugins not installed, rerun unreal-install-plugins" }
    ^notify-send -a Unreal "Unreal Engine" $"Installed ($version)" | complete | ignore
}
