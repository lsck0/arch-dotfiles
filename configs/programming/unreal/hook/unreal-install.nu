#!/usr/bin/env -S nu --no-config-file

const PLUGINS_INSTALL = path self | path expand | path dirname --num-levels 2 | path join unreal-install-plugins.nu
const ZIP_GLOB = "Linux_Unreal_Engine_*.zip"
const EDITOR = "Engine/Binaries/Linux/UnrealEditor"
const ICON = "Engine/Source/Runtime/Launch/Resources/Linux/UnrealEngine.png"
const CANARY = '^[^\]\[*?]*/Private/[^\]\[*?/]+$'

def data-dir []: nothing -> path { $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) }

def engine-dir []: nothing -> path { data-dir | path join unreal-engine }

def zip-newest []: nothing -> any {
    glob ($nu.home-dir | path join sync vendor $ZIP_GLOB) | sort --natural | last
}

# Rewritten on every run, not only on an install, so a fix here reaches an installed engine.
def desktop-write [version: string]: nothing -> nothing {
    let file = data-dir | path join applications unreal-engine.desktop
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
    # dot apply and the path unit both run this: the second waits, then finds the first's stamp
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
    # not /tmp: ~60 GB and /tmp is tmpfs; the old engine goes only once the new one is whole
    let staging = $"($engine).new"
    rm --recursive --force $staging
    mkdir $staging
    # unzip fails only after tens of GB, and apparmor's deny-sensitive-home refuses every Private dir
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
    let root = [$staging] ++ (ls $staging | where type == dir | get name)
        | where {|d| ($d | path join Engine | path type) == dir } | get --optional 0
    if $root == null or not ($root | path join $EDITOR | path exists) {
        rm --recursive --force $staging
        fail $"no ($EDITOR) in ($name)"
    }
    $"($name)\n" | save --force ($root | path join .installed-from)
    if ($engine | path exists) and not $installed {
        mv $engine $"($engine).pre-dotfiles-(date now | format date '%Y%m%d%H%M%S')"
        print -e $"unreal: kept the existing ($engine) aside"
    }
    rm --recursive --force $engine
    mv $root $engine
    rm --recursive --force $staging
    desktop-write $version
    try { ^$PLUGINS_INSTALL } catch { print -e "unreal: plugins not installed, rerun unreal-install-plugins" }
    ^notify-send -a Unreal "Unreal Engine" $"Installed ($version)" | complete | ignore
}
