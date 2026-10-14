use module.nu *

export const meta = {packages: {pacman: [waydroid]}}

# the images waydroid's own ota channels serve (ota.waydro.id VANILLA.json and MAINLINE.json), pinned by content:
# vanilla lineageos, no gapps. bump all four together, the next apply swaps them in
const SYSTEM_URL = "https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_x86_64/lineage-20.0-20260927-VANILLA-waydroid_x86_64-system.zip/download"
const SYSTEM_SHA256 = "053552725bf4ae25e2d3f7e6f1947203294aa9d73dc17fe1f3abe646e5d3bd8a"
const VENDOR_URL = "https://sourceforge.net/projects/waydroid/files/images/vendor/waydroid_x86_64/lineage-20.0-20260927-MAINLINE-waydroid_x86_64-vendor.zip/download"
const VENDOR_SHA256 = "d911b8353f6c807b94790b1c41c67e863a9f3dcd1cf3ec0232351398235afd7a"
# a preinstalled images dir: init takes the images from here and never downloads, upgrades come only from the pins
const IMAGES = "/etc/waydroid-extra/images"
const CONFIG = "/var/lib/waydroid/waydroid.cfg"
# in [properties] they reach every base prop file waydroid writes; `waydroid prop set` needs a session and reaches one
const PROPS = {properties: {persist.waydroid.multi_windows: "true", persist.waydroid.cursor_on_subsurface: "true"}}
# android's own freeform settings, in the session user's binary xml, reachable only through a booted session's shell
const FREEFORM = [
    development_settings_enabled enable_freeform_support force_resizable_activities enable_sizecompat_freeform
]
const DEVPERM_RULES = "/etc/udev/rules.d/99-waydroid-devperm.rules"

def pins []: nothing -> string {
    $"($SYSTEM_SHA256) ($VENDOR_SHA256)"
}

def status []: nothing -> string {
    ^waydroid status | complete | get stdout
}

def session-up []: nothing -> bool {
    status | lines | any { $in =~ '^Session:.*RUNNING' }
}

# wsl has no binder and no gpu for the container
export def system [cfg: record] {
    if (which waydroid | is-empty) or $env.FORM_FACTOR? == "wsl" { return [] }
    let current = try { open --raw ($IMAGES | path join .pins) | str trim } catch { "" }
    let images = if $current == (pins) { [] } else {
        # extracted beside the dir and swapped in whole, so init never sees a system.img without its vendor.img
        [
            (fetch-file $SYSTEM_URL $SYSTEM_SHA256 $"($IMAGES).new/system.img" --extract system.img)
            (fetch-file $VENDOR_URL $VENDOR_SHA256 $"($IMAGES).new/vendor.img" --extract vendor.img)
            (step images-swap)
        ]
    }
    let up = session-up
    if not $up { log-info "waydroid: for freeform windows, apply again while a session runs (waydroid session start)" }
    [
        $images
        (if (status | str contains "not initialized") {
            exec waydroid-init [waydroid init] --creates $CONFIG
        } else { [] })
        # a changed prop reaches the base props through an offline upgrade
        (ini-merge $CONFIG $PROPS --then [waydroid upgrade --offline])
        # a session chmods the gpu render nodes and cameras to 0777 and never restores them; the rule pins the resting
        # mode to the render/video groups' 0660, and the leftover world bit goes now unless a live session needs it
        (file-copy 99-waydroid-devperm.rules $DEVPERM_RULES --then [udevadm control --reload-rules])
        (if $up { [] } else { step devperm-tighten })
        # the root container a user's `waydroid session start` and its desktop entries attach to
        (unit-enable waydroid-container.service --now)
        (if $up { step freeform } else { [] })
    ]
}

export def images-swap []: nothing -> nothing {
    pins | save --force $"($IMAGES).new/.pins"
    rm --recursive --force $IMAGES
    mv $"($IMAGES).new" $IMAGES
    # an initialized one keeps its data and props, only the overlay over the old images goes
    if not (status | str contains "not initialized") { ^waydroid upgrade --offline }
}

# fail-safe: a failed chmod leaves a node as waydroid set it, never more open
export def devperm-tighten []: nothing -> nothing {
    glob /dev/dri/renderD* | append (glob /dev/video*) | each {|node| ^chmod o-rwx $node | complete } | ignore
}

export def freeform []: nothing -> nothing {
    if (^waydroid shell -- getprop sys.boot_completed | complete | get stdout | str trim) != "1" { return }
    for setting in $FREEFORM {
        # captured, never a file: waydroid shell chowns its output to root
        let out = ^waydroid shell -- settings put global $setting 1 | complete
        if $out.exit_code != 0 {
            error make {msg: $"waydroid: settings put global ($setting) failed: ($out.stdout)($out.stderr)"}
        }
    }
}
