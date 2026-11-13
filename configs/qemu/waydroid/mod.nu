use module.nu *

export const meta = {packages: {pacman: [waydroid]}}

const IMAGE_TIMEOUT = 90min
const SYSTEM_URL = "https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_x86_64/lineage-20.0-20260927-VANILLA-waydroid_x86_64-system.zip/download"
const SYSTEM_SHA256 = "053552725bf4ae25e2d3f7e6f1947203294aa9d73dc17fe1f3abe646e5d3bd8a"
const VENDOR_URL = "https://sourceforge.net/projects/waydroid/files/images/vendor/waydroid_x86_64/lineage-20.0-20260927-MAINLINE-waydroid_x86_64-vendor.zip/download"
const VENDOR_SHA256 = "d911b8353f6c807b94790b1c41c67e863a9f3dcd1cf3ec0232351398235afd7a"
const IMAGES = "/etc/waydroid-extra/images"
const CONFIG = "/var/lib/waydroid/waydroid.cfg"
const PROPS = {properties: {persist.waydroid.multi_windows: "true", persist.waydroid.cursor_on_subsurface: "true"}}
const FREEFORM = [
    development_settings_enabled enable_freeform_support force_resizable_activities enable_sizecompat_freeform
]
const PINS = $"($SYSTEM_SHA256) ($VENDOR_SHA256)"
const PINS_FILE = ".pins"
const STAGED = $"($IMAGES).new"

def status []: nothing -> string {
    ^waydroid status | complete | get stdout
}

export def system [cfg: record] {
    if (which waydroid | is-empty) or $env.FORM_FACTOR? == "wsl" { return [] }
    let current = file-trim ($IMAGES | path join $PINS_FILE)
    let images = if $current != $PINS {
        [
            # about 1 GiB from sourceforge, slower than STEP_TIMEOUT allows on a throttled mirror
            (fetch-file $SYSTEM_URL $SYSTEM_SHA256 ($STAGED | path join system.img) --extract system.img --timeout $IMAGE_TIMEOUT)
            (fetch-file $VENDOR_URL $VENDOR_SHA256 ($STAGED | path join vendor.img) --extract vendor.img --timeout $IMAGE_TIMEOUT)
            (step images-swap --requires ($STAGED | path join vendor.img))
        ]
    }
    let status = status
    let up = $status | lines | any { $in =~ '^Session:.*RUNNING' }
    if not $up { log-note "waydroid: for freeform windows, apply again while a session runs (waydroid session start)" }
    [
        $images
        (if ($status | str contains "not initialized") {
            exec waydroid-init [waydroid init] --creates $CONFIG --network --requires ($IMAGES | path join $PINS_FILE)
        })
        # a merge planned before init would overwrite init's [waydroid] section with sectionless content
        (if ($CONFIG | path exists) {
            ini-merge $CONFIG $PROPS --then [waydroid upgrade --offline]
        })
        (udev-rules 70-waydroid-devperm.rules --subsystem-match=drm --subsystem-match=video4linux)
        (if not $up { step devperm-tighten })
        (unit-enable waydroid-container.service --now)
        (if $up { step freeform })
    ]
}

# Swaps the fetched images in whole, so init never sees a system.img without its vendor.img; one still downloading
# leaves the swap pending.
export def images-swap []: nothing -> nothing {
    for img in [system.img vendor.img] {
        if not ($STAGED | path join $img | path exists) {
            print $"waydroid: ($img) not fetched yet, not swapping"
            exit $EXIT_PENDING
        }
    }
    $PINS | save --force ($STAGED | path join $PINS_FILE)
    rm --recursive --force $IMAGES
    mv $STAGED $IMAGES
    if not (status | str contains "not initialized") { ^waydroid upgrade --offline }
}

# Undoes the 0777 a session leaves on render nodes and cameras.
export def devperm-tighten []: nothing -> nothing {
    glob /dev/dri/renderD* | append (glob /dev/video*) | each {|node| ^chmod o-rwx $node | complete } | ignore
}

export def freeform []: nothing -> nothing {
    if (^waydroid shell -- getprop sys.boot_completed | complete | get stdout | str trim) != "1" { return }
    for setting in $FREEFORM {
        let out = ^waydroid shell -- settings put global $setting 1 | complete
        if $out.exit_code != 0 {
            error make {msg: $"waydroid: settings put global ($setting) failed: ($out.stdout)($out.stderr)"}
        }
    }
}
