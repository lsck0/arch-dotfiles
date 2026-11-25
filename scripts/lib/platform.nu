# Machine facts, exported to modules as uppercase env vars (platform-has).

use state.nu [file-trim]
use options.nu [option-value-errors]

const PLATFORM_LOCAL_DIR = "/etc/dotfiles"
export const PLATFORM_NAME_FILE = "/etc/dotfiles/platform"
# what dot set calls the platform file, its keys below it: platform.label, platform.facts.homelab
export const PLATFORM_TARGET = "platform"
# the checkout's own machine platform and its options (`dot set --machine`), git-ignored
export const PLATFORM_REPO_LOCAL = [platforms/local.nuon platforms/local.options.nuon]
const FORM_FACTORS = [desktop laptop server vm wsl]
# How dot set lands a platform key: live is stored and read where it is used, apply waits for the next dot apply (both
# layers), packages for the next dot apply --packages.
export const PLATFORM_APPLY = [live apply packages]
# The facts a platform file may set, typed like module options (a string's format as a pattern); platform-env hands
# each, form_factor too, to modules as an uppercase env var.
export const PLATFORM_FACTS = {
    homelab: {type: bool, default: false, label: "Homelab", doc: "On the homelab: its DNS, mirror and services"}
    wireguard: {type: "string?", default: null, label: "WireGuard", doc: "The tunnel config in configs/secrets/keys, as wireguard/<name>.conf"}
    secure_boot_own_keys: {type: bool, default: false, label: "Own secure boot keys", doc: "Signs the boot chain with its own enrolled keys"}
    lsck0_snapshot: {type: "string?", default: null, pattern: '^\d{4}-\d{2}-\d{2}$', label: "lsck0 snapshot", doc: "Pins [lsck0] to a dated snapshot, YYYY-MM-DD"}
    offload: {type: "string?", default: null, choices: [target client], label: "Offload role", doc: "Runs offloaded jobs (target) or sends them (client)"}
}
# Every key of a platform file but facts, typed like module options. hostname names the platform and stays fixed.
const PLATFORM_KEYS = {
    hostname: {type: string, default: null, label: "Hostname", doc: "Set at install, /etc/hostname when unset", fixed: true}
    label: {type: "string?", default: null, label: "Label", doc: "The installer's menu entry", apply: live}
    form_factor: {type: "string?", default: null, choices: $FORM_FACTORS, label: "Form factor", doc: "Probed when unset", apply: apply}
    groups: {type: "list<string>", default: [], nonempty: true, label: "Groups", doc: "Groups or group/module; unset means all, never secrets", apply: apply}
    extra_packages: {type: "list<string>", default: [], label: "Extra packages", doc: "pacman packages beside the modules'", group: packages, apply: packages}
    packages_keep: {type: "list<string>", default: [], label: "Keep pacman", doc: "Installed by hand, never removed as undeclared", group: packages, apply: packages}
    flatpak_keep: {type: "list<string>", default: [], label: "Keep flatpak", doc: "Installed by hand, never removed as undeclared", group: packages, apply: packages}
    nix_keep: {type: "list<string>", default: [], label: "Keep nix", doc: "Installed by hand, never removed as undeclared", group: packages, apply: packages}
}
const PLATFORM_FACTS_KEY = "facts"
const PLATFORM_FACTS_GROUP = "facts"
const PLATFORM_FACTS_APPLY = "apply"
const PACKAGE_NAME = '^\S+$'
const GPU_VENDORS = {"0x1002": amd, "0x8086": intel, "0x10de": nvidia}

# Every group under configs/ but secrets, which is on wherever the submodule is pulled.
export def platform-groups-all [repo: path]: nothing -> list<string> {
    ls ($repo | path join configs) | where type == dir | get name | path basename | where $it != secrets | sort
}

# Every named platform's file, the options files left out.
export def platform-files [repo: path]: nothing -> list<path> {
    glob ($repo | path join platforms *.nuon) | where not ($it | str ends-with ".options.nuon") | sort
}

# A name with no platform file is an error, never a fallback to every group.
export def platform-file [repo: path]: nothing -> any {
    let name = file-trim $PLATFORM_NAME_FILE
    let named = if $name != "" { $repo | path join platforms $"($name).nuon" }
    let found = [($PLATFORM_LOCAL_DIR | path join platform.nuon) ($repo | path join $PLATFORM_REPO_LOCAL.0) $named]
        | compact | where ($it | path exists) | get --optional 0
    if $found == null and $named != null {
        let known = platform-files $repo | each { path parse | get stem } | str join ', '
        error make {msg: $"($PLATFORM_NAME_FILE) names '($name)', but there is no ($named) \(platforms: ($known)\); fix it with: echo <platform> | sudo tee ($PLATFORM_NAME_FILE)"}
    }
    $found
}

def platform-probe-form-factor []: nothing -> string {
    let virt = try { ^systemd-detect-virt | str trim } catch { "none" }
    if $virt == "wsl" { return "wsl" }
    if $virt != "none" { return "vm" }
    if (glob /sys/class/power_supply/BAT* | is-not-empty) { "laptop" } else { "desktop" }
}

# The spec of a platform key as a cell path below the file's record ([label], [facts homelab]), null for none; label,
# group and apply filled in.
export def platform-spec [cell: list<string>]: nothing -> any {
    let spec = if ($cell | length) == 2 and $cell.0 == $PLATFORM_FACTS_KEY {
        $PLATFORM_FACTS | get --optional $cell.1 | if $in != null { merge {group: $PLATFORM_FACTS_GROUP, apply: $PLATFORM_FACTS_APPLY} }
    } else if ($cell | length) == 1 and $cell.0 != $PLATFORM_FACTS_KEY {
        $PLATFORM_KEYS | get --optional $cell.0
    }
    if $spec == null { return null }
    {group: "", fixed: false, apply: live} | merge $spec
}

# Every platform key's cell path, the file's order, the facts last.
export def platform-cells []: nothing -> list<list<string>> {
    ($PLATFORM_KEYS | columns | each { [$in] }) ++ ($PLATFORM_FACTS | columns | each { [$PLATFORM_FACTS_KEY $in] })
}

# Why raw (a platform file's record) is no valid platform, each line naming file; empty when it is.
export def platform-errors [repo: path, raw: record, file: string]: nothing -> list<string> {
    let known = ($PLATFORM_KEYS | columns) ++ [$PLATFORM_FACTS_KEY]
    let unknown = $raw | columns | where $it not-in $known
    if ($unknown | is-not-empty) { return [$"($file): unknown keys ($unknown | str join ', '), known: ($known | str join ', ')"] }
    let facts = $raw | get --optional $PLATFORM_FACTS_KEY | default {}
    if not ($facts | describe | str starts-with record) { return [$"($file): facts is ($facts | describe), wants a record"] }
    let unknown_facts = $facts | columns | where $it not-in $PLATFORM_FACTS
    if ($unknown_facts | is-not-empty) {
        return [$"($file): unknown facts ($unknown_facts | str join ', '); a per-module setting is a module option"]
    }
    let keys = $raw | reject --optional $PLATFORM_FACTS_KEY | items {|key, value| platform-value-errors $repo [$key] $value $file } | flatten
    let typed = $facts | items {|fact, value| platform-value-errors $repo [$PLATFORM_FACTS_KEY $fact] $value $file } | flatten
    $keys ++ $typed
}

# Why value does not fit the platform key at cell: its type, choices and pattern, a list's entries, the groups' existence.
export def platform-value-errors [repo: path, cell: list<string>, value: any, file: string]: nothing -> list<string> {
    let spec = platform-spec $cell
    let id = $cell | drop | prepend $PLATFORM_TARGET | str join "."
    let name = $cell | last
    let typed = option-value-errors $id $name $spec $value $file
    if ($typed | is-not-empty) or not ($spec.type | str starts-with "list<") { return $typed }
    let where = $"($file): ($id).($name)"
    let malformed = $value | where {|v| ($v | describe) != "string" or not ($v =~ $PACKAGE_NAME) }
    if ($malformed | is-not-empty) { return [$"($where): ($malformed | to nuon) are no names"] }
    if ($spec.nonempty? | default false) and ($value | is-empty) {
        return [$"($where): empty, unset it with dot set --default ($id).($name) instead"]
    }
    if $cell != [groups] { return [] }
    let all = platform-groups-all $repo
    let bad = $value | where {|g| $g not-in $all and not ($repo | path join configs $g mod.nu | path exists) }
    if ($bad | is-not-empty) { [$"($where): ($bad | str join ', ') not a group or module in configs/"] } else { [] }
}

# The validated platform; no groups means all, form_factor falls back to FORM_FACTOR, then a probe.
export def platform-load [repo: path]: nothing -> record {
    let file = platform-file $repo
    let raw = if $file == null { {} } else { open $file }
    let errors = platform-errors $repo $raw ($file | default "platform")
    if ($errors | is-not-empty) { error make {msg: ($errors | str join "\n")} }
    let all = platform-groups-all $repo
    let groups = $raw.groups? | default [] | if ($in | is-empty) { $all } else { $in }
    let form_factor = $env.FORM_FACTOR? | default ($raw.form_factor? | default "")
        | if ($in | is-empty) { platform-probe-form-factor } else { $in }
    if $form_factor not-in $FORM_FACTORS { error make {msg: $"($file): form_factor '($form_factor)' is not one of ($FORM_FACTORS | str join ', ')"} }
    let facts = $raw | get --optional $PLATFORM_FACTS_KEY | default {}
    let options_file = if $file != null { let p = $file | path parse; $p.parent | path join $"($p.stem).options.nuon" }
    {
        file: $file
        hostname: ($raw.hostname? | default { open --raw /etc/hostname | str trim })
        form_factor: $form_factor
        groups: $groups
        extra_packages: ($raw.extra_packages? | default [])
        facts: ($PLATFORM_FACTS | columns | each {|name| [$name ($facts | get --optional $name)] } | into record | upsert form_factor $form_factor)
        packages_keep: ($raw.packages_keep? | default [])
        flatpak_keep: ($raw.flatpak_keep? | default [])
        nix_keep: ($raw.nix_keep? | default [])
        options_file: $options_file
        options: (if $options_file != null and ($options_file | path exists) { open $options_file } else { {} })
    }
}

# Each platform key as the settings window shows it: its spec, the value in effect and where it came from (platform:
# the file, default: the value in effect when unset, which the spec's default then is).
export def platform-rows [repo: path, platform: record]: nothing -> table {
    let raw = if $platform.file == null { {} } else { open $platform.file }
    platform-cells | each {|cell|
        let spec = platform-spec $cell
        let set = $raw | get --optional ($cell | into cell-path)
        let fallback = match $cell {
            [hostname] => (open --raw /etc/hostname | str trim)
            [form_factor] => ($env.FORM_FACTOR? | default --empty (platform-probe-form-factor))
            [groups] => (platform-groups-all $repo)
            _ => $spec.default
        }
        let choices = if $cell == [groups] { $fallback ++ ($set | default [] | where $it not-in $fallback) } else { $spec.choices? }
        $spec | merge {
            key: ($cell | str join ".")
            default: $fallback
            value: ($set | default $fallback)
            source: (if $set == null { "default" } else { "platform" })
        } | merge (if $choices == null { {} } else { {choices: $choices} })
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

# A laptop's built-in panel by output name.
export const INTERNAL_PANEL = '^(eDP|LVDS|DSI)-'

# The main output of a monitors list ({output, mode}, desktop/hyprland's option): the internal panel, else the
# largest, the first on a tie; null for none.
export def monitors-main [monitors: list<record>]: nothing -> any {
    let internal = $monitors | where output =~ $INTERNAL_PANEL
    if ($internal | is-not-empty) { return $internal.0.output }
    let sized = $monitors | each {|m|
        let size = $m.mode | parse --regex '(?<w>\d+)x(?<h>\d+)' | into int w h | get --optional 0 | default {w: 0, h: 0}
        {output: $m.output, area: ($size.w * $size.h)}
    }
    if ($sized | is-empty) { return null }
    $sized | where area == ($sized.area | math max) | first | get output
}

# GDK_SCALE a monitors list implies: the main output's scale rounded, at least 1; the form factor's when the main
# output has no numeric scale (none, or hyprland's "auto").
export def monitors-xwayland-scale [monitors: list<record>, main: any, form_factor: string]: nothing -> int {
    let scale = $monitors | where output == $main | get --optional 0.scale
    if ($scale | describe) not-in [int float] { return (display-xwayland-scale $form_factor) }
    [1 ($scale | math round | into int)] | math max
}

# Vram by pci address from nvidia-smi, as the proprietary driver puts none in sysfs; empty without it.
def nvidia-vram []: nothing -> record {
    if not ("/proc/driver/nvidia/version" | path exists) or (which nvidia-smi | is-empty) { return {} }
    let run = do { ^timeout 5 nvidia-smi --query-gpu=pci.bus_id,memory.total --format=csv,noheader,nounits } | complete
    if $run.exit_code != 0 { return {} }
    # its bus id carries an 8-digit domain where sysfs has 4
    $run.stdout | lines | parse --regex '^0*(?<bus>[0-9A-Fa-f]{4}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}\.[0-9]), *(?<mib>\d+)'
        | reduce --fold {} {|r, acc| $acc | insert ($r.bus | str lowercase) (($r.mib | into int) * 1MiB) }
}

# The DRM cards, best first: most vram, then the one the firmware booted on.
export def gpu-list []: nothing -> table {
    let nvidia = nvidia-vram
    glob /sys/class/drm/card[0-9]* | where ($it | path basename) =~ '^card\d+$' | each {|card|
        let dev = $card | path join device
        let read = {|f| file-trim ($dev | path join $f) }
        let pci = ^readlink -f $dev | path basename
        let render = ls ($dev | path join drm) | get name | path basename | where ($it | str starts-with renderD) | get --optional 0
        {
            index: ($card | path basename | str replace card "" | into int)
            vendor: ($GPU_VENDORS | get --optional (do $read vendor) | default other)
            vram: (do $read mem_info_vram_total | if ($in | is-empty) { $nvidia | get --optional $pci | default 0 } else { into int } | into filesize)
            boot_vga: ((do $read boot_vga) == "1")
            render: (if $render == null { null } else { $"/dev/dri/($render)" })
            by_path: $"/dev/dri/by-path/pci-($pci)-render"
        }
    } | sort-by vram boot_vga --reverse
}

# Hyprland's monitors without an agent's headless outputs; --all keeps disabled ones. Empty outside Hyprland.
export def monitors-live [--all]: nothing -> table {
    if (which hyprctl | is-empty) { return [] }
    try { ^hyprctl -j monitors ...(if $all { [all] } else { [] }) | from json } catch { [] } | where name !~ '^HEADLESS-'
}
