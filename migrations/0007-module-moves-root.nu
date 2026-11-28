# base/lact, base/portmaster, base/protonvpn, base/tablet, base/v4l-utils and base/v4l2loopback left base for the groups that use them: root's own
# options file (a server or custom machine) renames their entries, else the load fails on "is no module"
export const layer = "system"

use options.nu [options-nuon-set]
use platform.nu [PLATFORM_LOCAL_FILES]

export const MOVED = {
    "base/lact": "desktop/lact"
    "base/portmaster": "desktop/portmaster"
    "base/protonvpn": "core/proton/vpn"
    "base/tablet": "desktop/tablet"
    "base/v4l-utils": "desktop/v4l-utils"
    "base/v4l2loopback": "creating/v4l2loopback"
}

# Renames the moved modules' entries of the options file at path, its comments and layout kept.
export def options-moved [path: path]: nothing -> nothing {
    if not ($path | path exists) { return }
    let before = open --raw $path
    let values = $before | from nuon | default {}
    let after = $MOVED | items {|old, new| {old: $old, new: $new} } | where old in ($values | columns)
        | reduce --fold $before {|m, text|
            let moved = $values | get $m.old | items {|name, value| {name: $name, value: $value} }
                | reduce --fold $text {|o, t| $t | options-nuon-set [$m.new $o.name] $o.value }
            $moved | options-nuon-set [$m.old] null --remove
        }
    if $after != $before { $after | save --force $path }
}

export def up []: nothing -> nothing {
    options-moved $PLATFORM_LOCAL_FILES.1
}
