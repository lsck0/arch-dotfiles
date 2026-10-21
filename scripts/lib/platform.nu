# Machine facts: the platform file bootstrap installed, its groups, form factor and facts; the facts reach
# modules as uppercase env vars, read with platform-has.

use log.nu *

const PLATFORM_LOCAL_DIR = "/etc/dotfiles"
export const PLATFORM_NAME_FILE = "/etc/dotfiles/platform"
const FORM_FACTORS = [desktop laptop server vm wsl]
export const PLATFORM_FACTS = [form_factor homelab wireguard secure_boot_own_keys lsck0_snapshot]
const PLATFORM_KEYS = [hostname form_factor groups extra_packages facts packages_keep]

# Every group under configs/ but secrets, which is on wherever the submodule is pulled.
export def platform-groups-all [repo: path]: nothing -> list<string> {
    ls ($repo | path join configs) | where type == dir | get name | path basename | where $it != secrets | sort
}

# The first of /etc/dotfiles/platform.nuon, platforms/local.nuon and the installed platforms/<name>.nuon, or null.
export def platform-file [repo: path]: nothing -> any {
    let name = try { open --raw $PLATFORM_NAME_FILE | str trim } catch { "" }
    [
        ($PLATFORM_LOCAL_DIR | path join platform.nuon)
        ($repo | path join platforms local.nuon)
        (if $name != "" { $repo | path join platforms $"($name).nuon" })
    ] | compact | where ($it | path exists) | get --optional 0
}

export def platform-options-file [file: path]: nothing -> path {
    let parsed = $file | path parse
    $parsed.parent | path join $"($parsed.stem).options.nuon"
}

def platform-probe-form-factor []: nothing -> string {
    let virt = try { ^systemd-detect-virt | str trim } catch { "none" }
    if $virt == "wsl" {
        "wsl"
    } else if $virt != "none" {
        "vm"
    } else if (glob /sys/class/power_supply/BAT* | is-not-empty) {
        "laptop"
    } else {
        "desktop"
    }
}

# The validated platform; no groups means all, form_factor falls back to FORM_FACTOR, then a probe.
export def platform-load [repo: path]: nothing -> record {
    let file = platform-file $repo
    let raw = if $file == null { {} } else { open $file }
    let unknown = $raw | columns | where $it not-in $PLATFORM_KEYS
    if ($unknown | is-not-empty) {
        error make {msg: $"($file): unknown keys ($unknown | str join ', '), known: ($PLATFORM_KEYS | str join ', ')"}
    }
    let all = platform-groups-all $repo
    let groups = $raw.groups? | default [] | if ($in | is-empty) { $all } else { $in }
    let bad = $groups | where {|g| $g not-in $all and not ($repo | path join configs $g mod.nu | path exists) }
    if ($bad | is-not-empty) {
        error make {msg: $"($file): groups has ($bad | str join ', '), not a group or module in configs/"}
    }
    let form_factor = $env.FORM_FACTOR? | default ($raw.form_factor? | default "")
        | if ($in | is-empty) { platform-probe-form-factor } else { $in }
    if $form_factor not-in $FORM_FACTORS {
        error make {msg: $"($file): form_factor '($form_factor)' is not one of ($FORM_FACTORS | str join ', ')"}
    }
    let facts = $raw.facts? | default {}
    let unknown_facts = $facts | columns | where $it not-in $PLATFORM_FACTS
    if ($unknown_facts | is-not-empty) {
        error make {msg: $"($file): unknown facts ($unknown_facts | str join ', '); a per-module setting is a module option"}
    }
    let options_file = if $file == null { null } else { platform-options-file $file }
    {
        file: $file
        hostname: ($raw.hostname? | default (open --raw /etc/hostname | str trim))
        form_factor: $form_factor
        groups: $groups
        extra_packages: ($raw.extra_packages? | default [])
        facts: ($PLATFORM_FACTS | reduce --fold {} {|name, acc| $acc | insert $name ($facts | get --optional $name) } | upsert form_factor $form_factor)
        packages_keep: ($raw.packages_keep? | default [])
        options_file: $options_file
        options: (if $options_file != null and ($options_file | path exists) { open $options_file } else { {} })
    }
}

# The facts as uppercase env vars: true is "1", false and null empty.
export def platform-env [platform: record]: nothing -> record {
    $platform.facts | items {|name, value|
        let text = match ($value | describe) {
            "bool" => (if $value { "1" } else { "" })
            "nothing" => ""
            _ => ($value | into string)
        }
        {name: ($name | str uppercase), value: $text}
    } | transpose -r -d
}

# Whether the fact's env var from platform-env is set.
export def platform-has [fact: string]: nothing -> bool {
    $env | get --optional ($fact | str uppercase) | default "" | is-not-empty
}

# GDK_SCALE for X11 apps under force_zero_scaling: 1 on a laptop, else 2.
export def display-xwayland-scale [form_factor: string]: nothing -> int {
    if $form_factor == "laptop" { 1 } else { 2 }
}

const GPU_VENDORS = {"0x1002": amd, "0x8086": intel, "0x10de": nvidia}

# The DRM cards, best first: most vram, then the one the firmware booted on.
export def gpu-list []: nothing -> table {
    glob /sys/class/drm/card[0-9]* | where ($it | path basename) =~ '^card\d+$' | each {|card|
        let dev = $card | path join device
        let read = {|f| try { open --raw ($dev | path join $f) | str trim } catch { "" } }
        let pci = ^readlink -f $dev | path basename
        let render = ls ($dev | path join drm) | get name | path basename | where ($it | str starts-with renderD) | get --optional 0
        {
            index: ($card | path basename | str replace card "" | into int)
            vendor: ($GPU_VENDORS | get --optional (do $read vendor) | default other)
            vram: (do $read mem_info_vram_total | if ($in | is-empty) { 0 } else { into int } | into filesize)
            boot_vga: ((do $read boot_vga) == "1")
            render: (if $render == null { null } else { $"/dev/dri/($render)" })
            by_path: $"/dev/dri/by-path/pci-($pci)-render"
        }
    } | sort-by vram boot_vga --reverse
}
