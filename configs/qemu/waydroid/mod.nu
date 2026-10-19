use module.nu *

export const meta = {packages: {pacman: [waydroid]}}

# waydroid's ota images (ota.waydro.id); bump all four together
const SYSTEM_URL = "https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_x86_64/lineage-20.0-20260927-VANILLA-waydroid_x86_64-system.zip/download"
const SYSTEM_SHA256 = "053552725bf4ae25e2d3f7e6f1947203294aa9d73dc17fe1f3abe646e5d3bd8a"
const VENDOR_URL = "https://sourceforge.net/projects/waydroid/files/images/vendor/waydroid_x86_64/lineage-20.0-20260927-MAINLINE-waydroid_x86_64-vendor.zip/download"
const VENDOR_SHA256 = "d911b8353f6c807b94790b1c41c67e863a9f3dcd1cf3ec0232351398235afd7a"
const IMAGES = "/etc/waydroid-extra/images"
const CONFIG = "/var/lib/waydroid/waydroid.cfg"
# not `waydroid prop set`: it needs a session and reaches one prop file
const PROPS = {properties: {persist.waydroid.multi_windows: "true", persist.waydroid.cursor_on_subsurface: "true"}}
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

export def system [cfg: record] {
    if (which waydroid | is-empty) or $env.FORM_FACTOR? == "wsl" { return [] }
    let current = try { open --raw ($IMAGES | path join .pins) | str trim } catch { "" }
    let images = if $current == (pins) { [] } else {
        # extracted beside the dir and swapped in whole, so init never sees a system.img without its vendor.img
        (
            (fetch-file $SYSTEM_URL $SYSTEM_SHA256 $"($IMAGES).new/system.img" --extract system.img)
            ++ (fetch-file $VENDOR_URL $VENDOR_SHA256 $"($IMAGES).new/vendor.img" --extract vendor.img)
            ++ [(step images-swap)]
        )
    }
    let up = session-up
    if not $up { log-note "waydroid: for freeform windows, apply again while a session runs (waydroid session start)" }
    [
        $images
        (if (status | str contains "not initialized") {
            exec waydroid-init [waydroid init] --creates $CONFIG
        } else { [] })
        # a merge planned before init would overwrite init's [waydroid] section with sectionless content
        (if ($CONFIG | path exists) {
            [(ini-merge $CONFIG $PROPS --then [waydroid upgrade --offline])]
        } else { [] })
        # a session chmods render nodes and cameras to 0777 and never restores them
        (file-copy 99-waydroid-devperm.rules $DEVPERM_RULES --then [udevadm control --reload-rules])
        (if $up { [] } else { step devperm-tighten })
        (unit-enable waydroid-container.service --now)
        (if $up { step freeform } else { [] })
    ]
}

export def images-swap []: nothing -> nothing {
    pins | save --force $"($IMAGES).new/.pins"
    rm --recursive --force $IMAGES
    mv $"($IMAGES).new" $IMAGES
    if not (status | str contains "not initialized") { ^waydroid upgrade --offline }
}

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
