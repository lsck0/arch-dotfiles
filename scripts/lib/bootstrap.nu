# Install a machine from the Arch ISO or set up a fresh WSL distro: walks bootstrap/questions.nuon in order;
# unattended (no tty or BOOTSTRAP_ASSUME_YES=1) every answer comes from its BOOTSTRAP_* variable or its default.

use log.nu *
use state.nu [SYSTEM_REPO path-kind]
use system.nu [system-pack system-unpack]
use platform.nu [platform-groups-all PLATFORM_NAME_FILE]

const MIRRORLIST = "/etc/pacman.d/mirrorlist"
const MIRROR_COUNTRIES = "/etc/pacman.d/mirror-countries"
const MIRROR_CANDIDATES = 5
const MIRROR_KEEP = 5
const MIRROR_RANKED_MIN = 3
const MIRROR_AGE_H = 12
const MIRROR_DOWNLOAD_TIMEOUT_S = 5
const REFLECTOR_WAIT_S = 90
const GEO_TIMEOUT_S = 3
const HOMELAB_MIRROR = 'http://10.100.0.104:8090/archlinux/$repo/os/$arch'
const HOMELAB_MIRROR_PROBE = "http://10.100.0.104:8090/archlinux/core/os/x86_64/core.db"

const KBD_MODEL_MAP = "/usr/share/systemd/kbd-model-map"
const ESP_SIZE_MIB = 1024
const LUKS_NAME = "root"
const PART_TYPE_LUKS = "8309"
const PART_TYPE_ROOT = "8304"
const MOUNT = "/mnt"
const BTRFS_OPTS = "noatime,compress=zstd"
const SUBVOLS = [
    [name mount]; ["@" "/"] ["@home" "/home"] ["@log" "/var/log"] ["@pkg" "/var/cache/pacman/pkg"]
    ["@libvirt" "/var/lib/libvirt/images"] ["@ollama" "/var/lib/ollama"] ["@docker" "/var/lib/docker"]
]
const LUKS_FORMAT = [--type luks2 --cipher aes-xts-plain64 --key-size 512 --sector-size 4096 --pbkdf argon2id]
const LUKS_OPEN = [--allow-discards --perf-no_read_workqueue --perf-no_write_workqueue --persistent]
const PACSTRAP = [base linux linux-firmware mkinitcpio btrfs-progs cryptsetup binutils networkmanager sudo git zsh zram-generator libfido2 nushell]
const HOOKS = [base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck]
const CMDLINE_TAIL = "rw zswap.enabled=0 nmi_watchdog=0 slab_nomerge init_on_alloc=1 init_on_free=1 randomize_kstack_offset=on vsyscall=none page_alloc.shuffle=1"
const SECRETS_TOOLS = [age age-plugin-yubikey git-crypt pcsclite ccid libfido2 yubikey-manager]
const STAGE_STATE_DIR = "/var/lib/dotfiles-stage"
const STAGE_KEY_FILE = "/etc/cryptsetup-keys.d/root.key"
const STAGE_KEY_BYTES = 64
const STAGE_ESP_MARKER = "/boot/dotfiles-stage-in-progress"
const ISO_LOG_TARGET = "/var/log/lsck0-install.log"
const SETUP_MODE_VAR = "/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"
const REBOOT_DELAY = 10sec
const SYNC_WAIT_S = 120
const NETWORK_TIMEOUT_S = 10
const NETWORK_TRIES = 3
const NETWORK_BACKOFF = 3sec
const PING_TIMEOUT_S = 2
const PLATFORM_LOCAL = "/etc/dotfiles/platform.nuon"
const PLATFORM_LOCAL_OPTIONS = "/etc/dotfiles/platform.options.nuon"
const PLATFORM_NEW = "custom"
const SERVER = "server"
const PROFILE_CUSTOM = "custom"
const SBCTL_MODULE = "base/boot/sbctl"
const LOGIN_SHELL = "/usr/bin/zsh"
const HOME_GATEWAYS = "/etc/NetworkManager/home-gateways"
const MAC_PATTERN = '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'
const TUI_WIDTH = 72
const TUI_BOX_ROWS = 4
const TUI_INPUT_ROWS = 7
const TUI_TEXT_MARGIN = 6
const TUI_BACKTITLE = "arch-dotfiles bootstrap"
const QUESTIONS = path self bootstrap/questions.nuon

def assume []: nothing -> bool { $env.BOOTSTRAP_ASSUME_YES? == "1" }
def tui []: nothing -> bool { $env.BOOTSTRAP_TUI? == "1" }
def env-or [name: string]: nothing -> string { $env | get --optional $name | default "" }

def one-line [value: string, label: string]: nothing -> string {
    if $value =~ '[\n\r]' { die $"($label) must not contain a newline" }
    $value
}

def die [message: string] {
    if (tui) { ^clear }
    error make {msg: $message}
}

def questions-load []: nothing -> record { open $QUESTIONS }

def text-fill [text: string, values: record]: nothing -> string {
    $values | items {|name, value| {name: $name, value: $value} } | reduce --fold $text {|v, acc|
        let tag = $"{($v.name)}"
        if not ($acc | str contains $tag) { return $acc }
        let shown = if ($v.value | describe | str starts-with "list") { $v.value | str join " " } else { $v.value | default "" | into string }
        $acc | str replace --all $tag $shown
    }
}

def when-holds [when: any, c: record]: nothing -> bool {
    $when | default {} | items {|field, want|
        if $field not-in $c { error make {msg: $"($QUESTIONS): `when` names ($field), no answer or fact by that name"} }
        let have = $c | get $field
        if ($want | describe | str starts-with "list") { $have in $want } else { $have == $want }
    } | all {|held| $held }
}

def options-items [e: record, c: record]: nothing -> list<string> {
    $e.options | where {|o| when-holds $o.when? $c } | each {|o| [$o.value $o.label] } | flatten
}

def online []: nothing -> bool {
    let mirror = if ($MIRRORLIST | path exists) {
        open --raw $MIRRORLIST | lines | parse --regex '^\s*Server\s*=\s*(?<url>\S+)' | get --optional 0.url
    }
    let probes = [(if $mirror == null { "https://archlinux.org" } else { $mirror | str replace '$repo' core | str replace '$arch' x86_64 | $"($in)/core.db" }) https://github.com]
    for _ in 1..$NETWORK_TRIES {
        if ($probes | all {|u| (^curl -fsI -m $NETWORK_TIMEOUT_S $u | complete).exit_code == 0 }) { return true }
        sleep $NETWORK_BACKOFF
    }
    false
}

def --env tui-init []: nothing -> nothing {
    if (assume) or ($env.TERM? | default dumb) == "dumb" or (^test -t 0 | complete).exit_code != 0 { return }
    if (which dialog | is-empty) and not ((online) and (try { ^pacman -Sy --noconfirm --needed dialog; true } catch { false })) {
        log-warn "dialog unavailable, using plain prompts"
        return
    }
    $env.BOOTSTRAP_TUI = "1"
}

def --wrapped dlg [...args: string]: nothing -> string {
    # collected inside the try: a msgbox's empty stream piped out of it raises nu's "internal error"
    try { ^dialog --backtitle $TUI_BACKTITLE --cr-wrap --stdout ...$args | collect } catch { die (questions-load).messages.aborted }
}

def height [text: string, rows: int]: nothing -> string {
    ($text | ^fold -s -w ($TUI_WIDTH - $TUI_TEXT_MARGIN) | lines | length) + $rows | into string
}

def screen [title: string, kind: string, text: string, ...init: string]: nothing -> string {
    let rows = if $kind in [inputbox passwordbox] { $TUI_INPUT_ROWS } else { $TUI_BOX_ROWS }
    let extra = if $kind == "passwordbox" { [--insecure] } else { [] }
    dlg --title $title --no-collapse ...$extra $"--($kind)" $text (height $text $rows) ($TUI_WIDTH | into string) ...$init
}

def ask [m: record, check: closure, label: string, text: string, default: string]: nothing -> any {
    if (assume) { return $default }
    mut note = ""
    loop {
        let answer = if (tui) { screen $label inputbox $"($note)($text)" $default } else { input $"($label) [($default)]: " | if ($in | is-empty) { $default } else { $in } }
        if (do $check $answer) { return $answer }
        $note = $"(text-fill $m.not_valid {value: $answer})\n\n"
        if not (tui) { log-warn $note }
    }
}

def menu [title: string, text: string, default: string, items: list<string>]: nothing -> string {
    dlg --title $title --default-item $default --menu $text "0" ($TUI_WIDTH | into string) "0" ...$items
}

def menu-plain [label: string, default: string, items: list<string>]: nothing -> string {
    $items | chunks 2 | each {|i| print -e $"  ($i.0 | fill --width 16)($i.1)" } | ignore
    input $"($label) [($default)]: " | default --empty $default
}

def yes [title: string, text: string, --default-yes]: nothing -> bool {
    if (tui) {
        let default = if $default_yes { [] } else { [--defaultno] }
        # --stdout: else dialog draws into complete's pipe and the next enter answers a box never shown
        let status = (^dialog --backtitle $TUI_BACKTITLE --stdout --cr-wrap --title $title ...$default --yesno $text (height $text $TUI_BOX_ROWS) ($TUI_WIDTH | into string) | complete).exit_code
        if $status > 1 { die (questions-load).messages.aborted }
        $status == 0
    } else if $default_yes {
        (input $"($text) [Y/n] " | str lowercase) != "n"
    } else {
        (input $"($text) [y/N] " | str lowercase) == "y"
    }
}

def ask-password [m: record, label: string, hint: string, empty_ok: bool]: nothing -> any {
    if (assume) {
        if $empty_ok { return "" }
        die (text-fill $m.password_required {title: $label})
    }
    mut note = ""
    loop {
        let first = if (tui) { screen $label passwordbox $"($note)($hint)" } else { print -e $hint; input -s $"($label): " }
        if ($first | is-empty) {
            if $empty_ok { return "" }
            $note = $"($m.password_empty)\n\n"
            if not (tui) { die (text-fill $m.password_empty_plain {title: $label}) }
            continue
        }
        let second = if (tui) { screen $label passwordbox $m.password_again } else { print -e ""; input -s $m.password_again_plain }
        if not (tui) { print -e "" }
        if $first == $second { return $first }
        if not (tui) { die $m.password_mismatch_plain }
        $note = $"($m.password_mismatch)\n\n"
    }
}

def --wrapped in-target [root: string, ...cmd: string]: nothing -> nothing {
    if ($root | is-empty) { ^($cmd | first) ...($cmd | skip 1) } else { ^arch-chroot $root ...$cmd }
}

def keyfile-escape [value: string]: nothing -> string {
    $value | str replace --all '\' '\\' | str replace --all "\n" '\n' | str replace --all "\t" '\t' | str replace --all "\r" '\r'
    | str replace --regex '^ ' '\s'
}

def default-route []: nothing -> record {
    ^ip -j -4 route show default | from json | get --optional 0 | default {}
}

def home-gateway-mac []: nothing -> any {
    let route = default-route
    if ($route.gateway? | is-empty) or ($route.dev? | is-empty) { return null }
    ^ping -c 1 -W $PING_TIMEOUT_S -I $route.dev $route.gateway | complete | ignore
    let mac = ^ip -j neigh show $route.gateway dev $route.dev | from json | get --optional 0.lladdr | default "" | str lowercase
    if $mac =~ $MAC_PATTERN { $mac } else { null }
}

def home-ssid []: nothing -> string {
    let dev = default-route | get --optional dev | default ""
    if ($dev | is-empty) or (which iw | is-empty) { return "" }
    ^iw dev $dev link | complete | get stdout | lines | parse --regex '^\s*SSID: (?<ssid>.*)$' | get --optional 0.ssid | default ""
}

def mirrors-rank []: nothing -> nothing {
    if not ("/run/archiso" | path exists) or (which reflector | is-empty) { return }
    for _ in 1..$REFLECTOR_WAIT_S {
        if (^systemctl show -p ActiveState --value reflector.service | complete | get stdout | str trim) != "activating" { break }
        sleep 1sec
    }
    ^systemctl stop reflector.service | complete | ignore
    let country = try { ^curl -fsS -m $GEO_TIMEOUT_S https://www.cloudflare.com/cdn-cgi/trace | lines | parse "loc={loc}" | get 0.loc } catch { "" }
    log-info $"ranking mirrors by download rate(if ($country | is-empty) { '' } else { $' in ($country)' })"
    let tmp = mktemp --directory
    mut ranked: any = null
    for scope in ([$country worldwide] | where $it != "") {
        let where = if $scope == "worldwide" { [] } else { [--country $scope] }
        let run = command-stream reflector [reflector --verbose --protocol https --age $MIRROR_AGE_H --latest $MIRROR_CANDIDATES --fastest $MIRROR_KEEP --connection-timeout $GEO_TIMEOUT_S --download-timeout $MIRROR_DOWNLOAD_TIMEOUT_S ...$where --save ($tmp | path join list)]
        if $run.exit_code != 0 { continue }
        let rates = $run.output | lines | parse --regex '(?<url>\S+)\s+(?<rate>[\d.]+) KiB/s' | where {|r| ($r.rate | into float) > 0 }
        let servers = open --raw ($tmp | path join list) | lines | where ($it | str starts-with "Server") | each {|line|
            let url = $line | split row " " | last | str replace '$repo/os/$arch' ""
            $rates | where url == $url | get --optional 0 | if $in == null { null } else { {server: $line, rate: ($in.rate | into float)} }
        } | compact
        if ($servers | length) >= $MIRROR_RANKED_MIN {
            $ranked = {scope: $scope, servers: $servers}
            break
        }
    }
    rm --recursive --force $tmp
    if $ranked == null {
        log-warn "mirror ranking failed, keeping the iso's list"
        return
    }
    let fallback = open --raw $MIRRORLIST | lines | where ($it | str starts-with "Server") and $it not-in $ranked.servers.server
    [$"# ranked by dot internal bootstrap (date now | format date '%F'): the fastest https mirrors \(($ranked.scope)\) by download rate"]
    | append $ranked.servers.server | append ["" "# the list before ranking, the fallback"] | append $fallback
    | str join "\n" | $"($in)\n" | save --force $MIRRORLIST
    let urls = $ranked.servers.server | each { split row " " | last }
    let info = ^reflector --info --protocol https | complete | get stdout | split row "\n\n" | each {|block|
        let url = $block | lines | where ($it | str starts-with "https:") | get --optional 0
        let country = $block | lines | parse --regex '^country\s+:\s*(?<c>.*)$' | get --optional 0.c
        {url: $url, country: $country}
    } | where url != null and country != null and country != ""
    let order = $urls | each {|u| $info | where url == $u | get --optional 0.country } | compact | uniq
    if ($order | is-not-empty) { $"($order | str join ',')\n" | save --force $MIRROR_COUNTRIES }
    $ranked.servers | each {|s| log-info $"  ($s.rate | math round | fill --alignment right --width 8) KiB/s  ($s.server | str substring 9..)" } | ignore
    log-info $"($ranked.servers | length) mirrors ranked \(($ranked.scope)\), countries: ($order | str join ',')"
}

def user-setup [c: record]: nothing -> nothing {
    let root = $c.target_root
    let home = $"($root)/home/($c.username)"
    let repo_copy = $home | path join projects arch-dotfiles
    if not (in-target-ok $root id -u $c.username) {
        in-target $root useradd -m -G wheel -s $LOGIN_SHELL $c.username
    }
    $"($c.username):(one-line $c.user_password 'user password')\n" | in-target-input $root chpasswd
    in-target $root passwd -l root
    if ($c.root_password | is-not-empty) { $"root:(one-line $c.root_password 'root password')\n" | in-target-input $root chpasswd }
    # sudo skips a drop-in named with a dot, so this one is checked before it can lock anyone out
    let sudoers = $"($root)/etc/sudoers.d/10-wheel"
    ^install -Dm440 ($c.repo | path join configs base sudo 10-wheel) $"($sudoers).new"
    if not (in-target-ok $root visudo -cqf /etc/sudoers.d/10-wheel.new) { die "the wheel sudoers drop-in does not parse" }
    mv --force $"($sudoers).new" $sudoers
    if not ($repo_copy | path exists) {
        mkdir ($repo_copy | path dirname)
        ^cp -a $c.repo $repo_copy
    }
    let local = $"($root)($PLATFORM_LOCAL)"
    let local_options = $"($root)($PLATFORM_LOCAL_OPTIONS)"
    if $c.generic {
        mkdir ($local | path dirname)
        let facts = if $c.secure_boot == "own" { {facts: {secure_boot_own_keys: true}} } else { {} }
        let kind = if $c.form_factor in ["" wsl] { {} } else { {form_factor: $c.form_factor} }
        {hostname: $c.hostname} | merge $kind | merge {groups: $c.groups} | merge $facts | to nuon --indent 4 | save --force $local
        let options = $c.options | merge (if $c.secure_boot == "off" { {$SBCTL_MODULE: {enable: false}} } else { {} })
        if ($options | is-not-empty) {
            let kept = if ($local_options | path exists) { open $local_options } else { {} }
            $kept | merge deep $options | to nuon --indent 4 | save --force $local_options
        }
        rm --force $"($root)($PLATFORM_NAME_FILE)"
    } else {
        rm --force $local
        mkdir ($"($root)($PLATFORM_NAME_FILE)" | path dirname)
        $"($c.platform)\n" | save --force $"($root)($PLATFORM_NAME_FILE)"
    }
    let profile = $home | path join .config dotfiles profile.nuon
    if ($c.profile_file | is-not-empty) and not ($profile | path exists) { ^install -Dm644 $c.profile_file $profile }
    if ($c.profile_file | is-not-empty) and ("secrets" in (open $c.profile_file | get --optional capabilities | default [])) {
        let owners = $"($root)/var/lib/dotfiles/owners"
        mkdir ($owners | path dirname)
        $"($c.username)\n" | save --append $owners
    }
    if ($c.ssh_key | is-not-empty) {
        let keys = $home | path join .ssh authorized_keys
        mkdir ($keys | path dirname)
        ^chmod 700 ($keys | path dirname)
        $"($c.ssh_key)\n" | save --force $keys
        ^chmod 600 $keys
    }
    try { system-pack $c.repo | system-unpack $"($root)($SYSTEM_REPO)" (^git -C $c.repo rev-parse HEAD | str trim) } catch {|e| die $"cannot seed the root copy ($root)($SYSTEM_REPO): ($e.msg)" }
    in-target $root chown -R $"($c.username):($c.username)" $"/home/($c.username)"
}

def --wrapped in-target-ok [root: string, ...cmd: string]: nothing -> bool {
    (do { in-target $root ...$cmd } | complete).exit_code == 0
}

def --wrapped in-target-input [root: string, ...cmd: string]: string -> nothing {
    let text = $in
    if ($root | is-empty) { $text | ^($cmd | first) ...($cmd | skip 1) } else { $text | ^arch-chroot $root ...$cmd }
}

def pacman-init []: nothing -> nothing {
    ^pacman-key --init
    ^pacman-key --populate archlinux
    ^pacman -Sy --noconfirm --needed archlinux-keyring
    ^pacman -Su --noconfirm --needed git gnupg sudo zsh nushell
}

def iwd-get [text: string, section: string, key: string]: nothing -> string {
    $text | lines | reduce --fold {in: false, value: ""} {|l, acc|
        if ($l | str starts-with "[") { $acc | update in (($l | str trim) == $"[($section)]") } else if $acc.in and ($l | str starts-with $"($key)=") {
            $acc | update value ($l | str substring ($key | str length | $in + 1)..)
        } else { $acc }
    } | get value
}

def wifi-sae-only []: nothing -> list<string> {
    if (which iw | is-empty) { return [] }
    ls /sys/class/net | get name | where { path join wireless | path exists } | path basename | each {|dev|
        ^iw dev $dev scan dump | complete | get stdout | split row --regex '(?m)^BSS ' | each {|bss|
            let ssid = $bss | lines | parse --regex '^\s*SSID: (?<s>.*)$' | get --optional 0.s
            let akm = $bss | lines | parse --regex 'Authentication suites: (?<a>.*)$' | get a | str join " " | split row " "
            if $ssid != null and "SAE" in $akm and "PSK" not-in $akm { $ssid }
        } | compact
    } | flatten | uniq
}

def wifi-carry [c: record]: nothing -> nothing {
    let sae_only = wifi-sae-only
    for f in (glob /var/lib/iwd/*.{psk,open}) {
        let name = $f | path parse | get stem
        let open = ($f | path parse | get extension) == "open"
        let ssid = if ($name | str starts-with "=") { $name | str substring 1.. | decode hex | decode utf-8 } else { $name }
        let text = open --raw $f
        let psk = iwd-get $text Security Passphrase | default --empty (iwd-get $text Security PreSharedKey)
        if not $open and ($psk | is-empty) { continue }
        let security = if $open { [] } else {
            let mgmt = if $ssid in $sae_only and ($psk | str length) != 64 { "sae" } else { "wpa-psk" }
            ["" "[wifi-security]" $"key-mgmt=($mgmt)" $"psk=(keyfile-escape $psk)"]
        }
        let hidden = if (iwd-get $text Settings Hidden) == "true" { ["hidden=true"] } else { [] }
        let mac = if $c.home_gateway != null and $ssid == $c.home_ssid { ["cloned-mac-address=permanent"] } else { [] }
        let bytes = $ssid | encode utf-8 | chunks 1 | each {|b| $"($b | into int);" } | str join
        let file = $"($MOUNT)/etc/NetworkManager/system-connections/($name).nmconnection"
        mkdir ($file | path dirname)
        (["[connection]" $"id=(keyfile-escape $ssid)" "type=wifi" "" "[wifi]" $"ssid=($bytes)"] ++ $mac ++ $hidden ++ $security
            ++ ["" "[ipv4]" "method=auto" "" "[ipv6]" "method=auto"])
        | str join "\n" | $"($in)\n" | save --force $file
        ^chmod 600 $file
    }
}

def xkb-vars [keymap: string]: nothing -> list<string> {
    let row = if ($KBD_MODEL_MAP | path exists) {
        open --raw $KBD_MODEL_MAP | lines | parse --regex '^(?<console>\S+)\s+(?<layout>\S+)\s+\S+\s+(?<variant>\S+)'
        | where console == $keymap | get --optional 0
    }
    if $row == null { return [] }
    [$"XKBLAYOUT=($row.layout)"] ++ (if $row.variant == "-" { [] } else { [$"XKBVARIANT=($row.variant)"] })
}

def target-system [c: record, root_uuid: string]: nothing -> nothing {
    let t = {|path| $"($MOUNT)($path)" }
    ^ln -sf $"/usr/share/zoneinfo/($c.timezone)" (do $t /etc/localtime)
    in-target $MOUNT hwclock --systohc
    open --raw (do $t /etc/locale.gen) | str replace --regex --multiline $"^#\(($c.locale) \)" '$1' | save --force (do $t /etc/locale.gen)
    in-target $MOUNT locale-gen
    $"LANG=($c.locale)\n" | save --force (do $t /etc/locale.conf)
    [$"KEYMAP=($c.keymap)"] ++ (xkb-vars $c.keymap) | str join "\n" | $"($in)\n" | save --force (do $t /etc/vconsole.conf)
    $"($c.hostname)\n" | save --force (do $t /etc/hostname)
    $"127.0.0.1 localhost\n::1 localhost\n127.0.1.1 ($c.hostname)\n" | save --force (do $t /etc/hosts)
    mkdir (do $t /etc/kernel)
    let root = if $c.encrypt { $"rd.luks.name=($root_uuid)=($LUKS_NAME) root=/dev/mapper/($LUKS_NAME)" } else { $"root=UUID=($root_uuid)" }
    $"($root) rootflags=subvol=@ ($CMDLINE_TAIL)\n" | save --force (do $t /etc/kernel/cmdline)
    let hooks = $HOOKS | where $c.encrypt or $it != "sd-encrypt" | str join " " | $"HOOKS=\(($in)\)"
    open --raw (do $t /etc/mkinitcpio.conf) | str replace --regex --multiline '^HOOKS=.*$' $hooks | save --force (do $t /etc/mkinitcpio.conf)
    for preset in (glob (do $t /etc/mkinitcpio.d/*.preset)) {
        let pkgbase = $preset | path parse | get stem
        open --raw $preset | lines | where not ($it =~ '^#?default_(image|uki|cmdline)=') | each { str replace --regex '^PRESETS=.*' "PRESETS=('default')" }
        | append [$"default_uki=\"/boot/EFI/Linux/arch-($pkgbase).efi\"" 'default_cmdline="/etc/kernel/cmdline"'] | str join "\n" | $"($in)\n" | save --force $preset
        rm --force (do $t $"/boot/initramfs-($pkgbase).img") (do $t $"/boot/initramfs-($pkgbase)-fallback.img")
    }
    mkdir (do $t /boot/EFI/Linux)
    in-target $MOUNT mkinitcpio -P
    in-target $MOUNT systemctl enable NetworkManager.service NetworkManager-wait-online.service systemd-timesyncd.service
    in-target $MOUNT bootctl install --esp-path=/boot --variables=yes
    ^install -Dm644 ($c.repo | path join configs base zram zram-generator.conf) (do $t /etc/systemd/zram-generator.conf)
}

def boot-next-installed [esp: string]: nothing -> nothing {
    if (which efibootmgr | is-empty) { return }
    let partuuid = ^lsblk -dno PARTUUID $esp | str trim | str lowercase
    let entry = ^efibootmgr -v | complete | get stdout | lines
        | parse --regex '^Boot(?<num>[0-9A-Fa-f]{4})\*?\s+Linux Boot Manager\s(?<path>.*)$'
        | where {|b| ($partuuid | is-not-empty) and ($b.path | str lowercase | str contains $partuuid) } | get --optional 0.num
    if $entry == null { log-warn "no firmware entry for the new ESP, remove the stick before the next boot"; return }
    ^efibootmgr --quiet --bootnext $entry
}

def stage-arm [c: record, root_uuid: string]: nothing -> nothing {
    let state = $"($MOUNT)($STAGE_STATE_DIR)"
    mkdir $state
    "install\n" | save --force ($state | path join next)
    if $c.encrypt { $"/dev/disk/by-uuid/($root_uuid)\n" | save --force ($state | path join luks-device) }
    let report = env-or BOOTSTRAP_REPORT
    if $report != "" { $"($report)\n" | save --force ($state | path join report) }
    $"($c.username) ALL=\(ALL:ALL\) NOPASSWD: ALL\nDefaults:($c.username) verifypw=any\n" | save --force $"($MOUNT)/etc/sudoers.d/zz-dotfiles-stage"
    ^chmod 440 $"($MOUNT)/etc/sudoers.d/zz-dotfiles-stage"
    "a dotfiles install chain runs from this disk; the lsck0 iso will not erase it unattended\n" | save --force $"($MOUNT)($STAGE_ESP_MARKER)"
    let checkout = $"/home/($c.username)/projects/arch-dotfiles"
    [
        "[Unit]" "Description=arch-dotfiles install chain (dot internal stage)" "Wants=network-online.target"
        "After=network-online.target" $"ConditionPathExists=($STAGE_STATE_DIR)/next" "" "[Service]" "Type=exec"
        $"User=($c.username)" "PAMName=login" $"WorkingDirectory=($checkout)" "ExecStartPre=-/usr/bin/nm-online -q -t 120"
        $"ExecStart=/usr/bin/nu --no-config-file ($checkout)/scripts/dot.nu internal stage" "StandardOutput=tty"
        "TimeoutStartSec=infinity" "" "[Install]" "WantedBy=multi-user.target"
    ] | str join "\n" | $"($in)\n" | save --force $"($MOUNT)/etc/systemd/system/dotfiles-stage.service"
    in-target $MOUNT systemctl enable dotfiles-stage.service
}

def on-archiso []: nothing -> bool {
    ("/run/archiso" | path exists) and (open --raw /proc/cmdline | str contains "archisobasedir=")
}

def on-wsl []: nothing -> bool {
    open --raw /proc/sys/kernel/osrelease | str lowercase | str contains microsoft
}

def platform-names [repo: path]: nothing -> list<string> {
    glob ($repo | path join platforms *.nuon) | where not ($it | str ends-with ".options.nuon") | each { path parse | get stem } | sort
}

def platform-items [e: record, c: record]: nothing -> list<string> {
    let fixed = platform-names $c.repo | where $it not-in $e.hidden | each {|p|
        {name: $p, form_factor: (open ($c.repo | path join platforms $"($p).nuon") | get --optional form_factor | default "")}
    } | where {|p| ($p.form_factor == "wsl") == $c.host_wsl } | each {|p|
        [$p.name ($e.form_factors | get --optional $p.form_factor | default $p.form_factor)]
    } | flatten
    $fixed ++ (options-items $e $c)
}

# The profiles/<picked> name and its capabilities; custom has none and copies no file.
export def bootstrap-profile-resolve [repo: path, e: record, picked: string]: nothing -> record {
    if $picked == $PROFILE_CUSTOM { return {profile: $PROFILE_CUSTOM, profile_file: "", capabilities: []} }
    let names = glob ($repo | path join profiles *.nuon) | each { path parse | get stem } | sort
    if $picked not-in $names { die (text-fill $e.invalid {value: $picked, choices: ($names ++ $e.options.value)}) }
    let file = $repo | path join profiles $"($picked).nuon"
    {profile: $picked, profile_file: $file, capabilities: (open $file | get --optional capabilities | default [])}
}

# The picked platform; custom with BOOTSTRAP_SERVER=1 becomes server, both generic (no platforms/ file).
export def bootstrap-platform-resolve [repo: path, e: record, picked: string, wsl: bool]: nothing -> record {
    let server_flag = env-or BOOTSTRAP_SERVER
    if $server_flag not-in ["" "0" "1"] { die (text-fill (questions-load).messages.flag_invalid {env: BOOTSTRAP_SERVER, value: $server_flag}) }
    let name = if $picked == $PLATFORM_NEW and $server_flag == "1" { $SERVER } else { $picked }
    if $name == $SERVER and $wsl { die $e.invalid_wsl }
    if $name in [$PLATFORM_NEW $SERVER] { return {platform: $name, generic: true, server: ($name == $SERVER)} }
    let names = platform-names $repo
    if $name not-in $names { die (text-fill $e.invalid {value: $name, choices: (($names | where $it not-in $e.hidden) ++ $e.options.value)}) }
    {platform: $name, generic: false, server: false}
}

def answer-valid [e: record, value: string, c: record]: nothing -> bool {
    if ($value | is-empty) and ($e.empty_ok? | default false) { return true }
    if $e.pattern? != null and $value !~ $e.pattern { return false }
    match $e.id {
        "hostname" => ($value not-in $c.platforms)
        "timezone" => ($"/usr/share/zoneinfo/($value)" | path exists)
        "locale" => ($value in (open --raw /etc/locale.gen | lines | each { str replace --regex '^#' '' | split row " " | first }))
        "keymap" => ((^loadkeys $value | complete).exit_code == 0)
        _ => true
    }
}

def answer-invalid [e: record, value: string, c: record, choices: list<string> = []]: nothing -> nothing {
    die (text-fill $e.invalid ($c | merge {value: $value, choices: $choices, pattern: ($e.pattern? | default "")}))
}

def answer-text [m: record, e: record, c: record]: nothing -> string {
    let default = if ($e.default? | describe | str starts-with "record") { $e.default | get --optional $c.platform } else { $e.default? }
    let given = env-or $e.env
    let value = if ($given | is-not-empty) { $given } else if (assume) {
        if $default == null { die (text-fill $m.required $e) }
        $default
    } else {
        ask $m {|v| answer-valid $e $v $c } (text-fill $e.title $c) (text-fill $e.text $c) ($default | default "")
    }
    if not (answer-valid $e $value $c) { answer-invalid $e $value $c }
    $value
}

def answer-flag [m: record, e: record, c: record]: nothing -> bool {
    let value = env-or $e.env | if ($in | is-not-empty) { $in } else if (assume) { if $e.default { "1" } else { "0" } } else {
        if (yes (text-fill $e.title $c) (text-fill $e.text $c) --default-yes=$e.default) { "1" } else { "0" }
    }
    if $value not-in ["0" "1"] { die (text-fill $m.flag_invalid {env: $e.env, value: $value}) }
    $value == "1"
}

def answer-menu [e: record, c: record]: nothing -> string {
    let items = options-items $e $c
    let value = env-or $e.env | if ($in | is-not-empty) or (assume) { $in | default --empty $e.default } else if (tui) {
        menu (text-fill $e.title $c) (text-fill $e.text $c) $e.default $items
    } else {
        menu-plain (text-fill $e.title $c) $e.default $items
    }
    let values = $e.options.value
    if $value not-in $values { die (text-fill $e.invalid {value: $value, choices: ($values | str join ", ")}) }
    $value
}

# BOOTSTRAP_KEYMAP answers; BOOTSTRAP_KEYMAP_DEFAULT (the iso stub's Wi-Fi password keymap) only preselects
def answer-keymap [m: record, e: record, c: record]: nothing -> string {
    let valid = {|k| answer-valid $e $k $c }
    let given = env-or $e.env
    let preset = $env.BOOTSTRAP_KEYMAP_DEFAULT? | default "" | if ($in | is-empty) { $e.default } else { $in }
    let listed = $preset in $e.options.value
    let keymap = if ($given | is-not-empty) { $given } else if not (tui) { ask $m $valid $e.other.title "" $preset } else {
        let picked = menu $e.title $e.text (if $listed { $preset } else { $e.other.value }) ((options-items $e $c) ++ [$e.other.value $e.other.label])
        if $picked != $e.other.value { $picked } else { ask $m $valid $e.other.title $e.other.text (if $listed { "" } else { $preset }) }
    }
    if not (do $valid $keymap) { answer-invalid $e $keymap $c }
    $keymap
}

def answer-password [m: record, e: record, c: record]: nothing -> string {
    env-or $e.env | if ($in | is-not-empty) { $in } else {
        ask-password $m (text-fill $e.title $c) (text-fill $e.text $c) ($e.empty_ok? | default false)
    }
}

def answer-profile [e: record, c: record]: nothing -> record {
    let given = env-or $e.env
    let picked = if ($given | is-not-empty) { $given } else if (assume) { $e.default } else {
        let named = glob ($c.repo | path join profiles *.nuon) | sort | each {|f|
            let p = open $f
            let stem = $f | path parse | get stem
            [$stem (text-fill $e.file_label {name: ($p.name? | default $stem), capabilities: ($p.capabilities? | default [] | str join ", ")})]
        } | flatten
        let items = $named ++ (options-items $e $c)
        if (tui) { menu $e.title $e.text $e.default $items } else { menu-plain $e.title $e.default $items }
    }
    bootstrap-profile-resolve $c.repo $e $picked
}

def answer-platform [e: record, c: record]: nothing -> record {
    let given = [$c.platform_arg (env-or $e.env)] | where $it != "" | get --optional 0
    let picked = if $given != null { $given } else if (assume) { $e.default } else {
        let items = platform-items $e $c
        if (tui) { menu $e.title $e.text $e.default $items } else { menu-plain $e.title $e.default $items }
    }
    bootstrap-platform-resolve $c.repo $e $picked $c.host_wsl
}

def answer-groups [e: record, c: record]: nothing -> list<string> {
    let universe = platform-groups-all $c.repo
    let required = {required: $e.required}
    let chosen = if $c.server { $c.groups } else if (env-or $e.env | is-not-empty) {
        env-or $e.env | split row --regex '\s+' | where $it != ""
    } else if (assume) { $universe } else if (tui) {
        let items = $universe | where $it != $e.required | each {|g| [$g ($e.options | where value == $g | get --optional 0.label | default "") on] } | flatten
        dlg --title $e.title --separate-output --checklist (text-fill $e.text $required) "0" ($TUI_WIDTH | into string) "0" ...$items | lines
    } else {
        print -e (text-fill $e.plain $required)
        $universe | enumerate | each { print -e $"  ($in.index + 1)  ($in.item)" } | ignore
        let excludes = input $e.plain_prompt | split row " " | where $it != ""
        $universe | enumerate | where {|g| ($g.index + 1 | into string) not-in $excludes } | get item
    }
    let groups = [$e.required] ++ ($chosen | where $it != $e.required)
    let unknown = $groups | where {|g| ($g | path split | first) not-in $universe }
    if ($unknown | is-not-empty) { answer-invalid $e ($unknown | first) $c $universe }
    $groups
}

def stage-in-progress [disk: string]: nothing -> bool {
    let esps = ^lsblk -J -lnpo NAME,TYPE,FSTYPE $disk | from json | get blockdevices | where type == part and fstype == vfat | get name
    let dir = mktemp --directory
    let found = $esps | any {|p|
        if (^mount -o ro $p $dir | complete).exit_code != 0 { return false }
        let has = ($dir | path join ($STAGE_ESP_MARKER | path basename) | path exists)
        ^umount $dir | complete | ignore
        $has
    }
    rm --recursive --force $dir
    $found
}

def disk-release [disk: string]: nothing -> nothing {
    let devs = ^lsblk -J -lnpo NAME,TYPE,MOUNTPOINTS $disk | from json | get blockdevices
    $devs | where {|d| "[SWAP]" in ($d.mountpoints | compact) } | each { ^swapoff $in.name | complete } | ignore
    if (which pvs | is-not-empty) {
        ^pvs --noheadings -o pv_name,vg_name | lines | parse --regex '^\s*(?<pv>\S+)\s+(?<vg>\S+)' | where pv in $devs.name
        | get vg | uniq | each { ^vgchange -an $in | complete } | ignore
    }
    $devs | reverse | each {|d|
        if $d.type == "crypt" { ^cryptsetup close $d.name | complete } else if ($d.type | str starts-with "raid") { ^mdadm --stop $d.name | complete }
    } | ignore
}

def disk-model [disk: string]: nothing -> string {
    ^lsblk -dno SIZE,MODEL $disk | str trim | str replace --all --regex '\s+' ' '
}

def answer-disk [m: record, e: record, c: record]: nothing -> record {
    let disks = ^lsblk -J -dnpo NAME,TYPE,RM | from json | get blockdevices | where type == disk and rm == false and not ($it.name =~ 'zram|loop') | get name
    let disk = env-or $e.env | if ($in | is-not-empty) { $in } else if ($disks | is-empty) {
        die $e.none
    } else if ($disks | length) == 1 { $disks.0 } else if (assume) {
        die (text-fill $e.several {choices: ($disks | str join " ")})
    } else if (tui) {
        menu $e.title $e.text $disks.0 ($disks | each {|d| [$d (disk-model $d)] } | flatten)
    } else {
        ^lsblk -dpo NAME,SIZE,MODEL ...$disks
        input (text-fill $e.plain {choices: $disks})
    }
    if (path-kind $disk) == "" or (^test -b $disk | complete).exit_code != 0 { die (text-fill $e.invalid {value: $disk}) }
    if (^lsblk -dno TYPE $disk | complete | get stdout | str trim) != "disk" { die (text-fill $e.invalid_part {value: $disk}) }
    if (assume) and (env-or BOOTSTRAP_REINSTALL) != "1" and (stage-in-progress $disk) { die (text-fill $e.in_progress {disk: $disk}) }
    let layout = ^lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL $disk
    let erase = text-fill $e.confirm.text {disk: $disk}
    let typed = if (assume) { $disk } else if (tui) { screen $e.confirm.title inputbox $"($layout)\n\n($erase)" } else { print $layout; input $"($erase) " }
    if $typed != $disk { die $m.aborted }
    {disk: $disk, disk_model: (disk-model $disk)}
}

def question-ask [q: record, e: record, c: record]: nothing -> record {
    let m = $q.messages
    let one = {|value| {} | insert $e.id $value }
    match $e.kind {
        "text" => (do $one (answer-text $m $e $c))
        "password" => (do $one (answer-password $m $e $c))
        "flag" => (do $one (answer-flag $m $e $c))
        "menu" => (do $one (answer-menu $e $c))
        "keymap" => (do $one (answer-keymap $m $e $c))
        "groups" => (do $one (answer-groups $e $c))
        "profile" => (answer-profile $e $c)
        "platform" => (answer-platform $e $c)
        "disk" => (answer-disk $m $e $c)
        _ => (error make {msg: $"($QUESTIONS): ($e.id) has kind ($e.kind), not one bootstrap.nu asks"})
    }
}

def step-home-network [q: record, c: record]: nothing -> record {
    let gateway = if $c.home_network { home-gateway-mac } else { null }
    if $c.home_network and $gateway == null { log-warn $q.messages.no_router }
    $c | merge {home_gateway: $gateway, home_ssid: (if $c.home_network { home-ssid } else { "" })}
}

def step-platform-load [q: record, c: record]: nothing -> record {
    let c = if not $c.generic {
        let file = $c.repo | path join platforms $"($c.platform).nuon"
        let p = open $file
        if ($p.hostname? | is-empty) { die $"($file) sets no hostname" }
        let all = platform-groups-all $c.repo
        let options = $c.repo | path join platforms $"($c.platform).options.nuon" | if ($in | path exists) { open $in } else { {} }
        let secure_boot = if ($options | get --optional $SBCTL_MODULE | get --optional enable) == false { "off" } else if ($p.facts?.secure_boot_own_keys? | default false) { "own" } else { "microsoft" }
        $c | merge {hostname: $p.hostname, groups: ($p.groups? | default $all), form_factor: ($p.form_factor? | default ""), homelab: ($p.facts?.homelab? | default false), secure_boot: $secure_boot}
    } else if $c.server {
        let template = $c.repo | path join platforms $"($SERVER).nuon"
        let options = $template | path parse | $"($in.parent)/($in.stem).options.nuon"
        $c | merge {form_factor: $SERVER, groups: (open $template | get groups), options: (if ($options | path exists) { open $options } else { {} })}
    } else if $c.host_wsl { $c | merge {form_factor: "wsl"} } else { $c }
    let machine_wsl = $c.form_factor == "wsl"
    if $machine_wsl and not $c.host_wsl { die (text-fill $q.messages.wsl_machine $c) }
    $c | merge {machine_wsl: $machine_wsl}
}

def step-install-checks [q: record, c: record]: nothing -> record {
    let m = $q.messages
    if not (on-archiso) { die $m.not_iso }
    if not ("/sys/firmware/efi" | path exists) { die $m.not_uefi }
    if not (online) { die $m.offline }
    let setup_mode = (try { open --raw $SETUP_MODE_VAR | into binary | last 1 | into int } catch { 0 }) == 1
    if $c.secure_boot != "off" and not $setup_mode and not (assume) and not (yes $m.setup_mode.title $m.setup_mode.text) {
        die $m.setup_mode_stop
    }
    $c | merge {setup_mode: $setup_mode}
}

def step-run [q: record, step: string, c: record]: nothing -> record {
    match $step {
        "home-network" => (step-home-network $q $c)
        "platform-load" => (step-platform-load $q $c)
        "install-checks" => (step-install-checks $q $c)
        _ => (error make {msg: $"($QUESTIONS): no step ($step) in bootstrap.nu"})
    }
}

def questions-walk [q: record, c: record]: nothing -> record {
    $q.questions | reduce --fold $c {|e, c|
        if not (when-holds $e.when? $c) { $c } else if $e.step? != null { step-run $q $e.step $c } else { $c | merge (question-ask $q $e $c) }
    }
}

def question-defaults [q: record]: nothing -> record {
    $q.questions | where {|e| $e.id? != null and $e.default? != null and not ($e.default | describe | str starts-with "record") }
    | reduce --fold {} {|e, acc| $acc | upsert $e.id $e.default }
}

def summary-render [q: record, c: record]: nothing -> string {
    let s = $q.summary
    let width = ($s.rows | values | each { str length } | math max) + 1
    $s.rows | items {|row, label|
        let value = match $row {
            "login" => $c.username
            "profile" => $"($c.profile) \((if ($c.capabilities | is-empty) { $s.profile_none } else { $c.capabilities | str join ' ' })\)"
            "machine" => $c.platform
            "hostname" => $c.hostname
            "keyboard" => $c.keymap
            "timezone" => $c.timezone
            "locale" => $c.locale
            "groups" => ($c.groups | str join " ")
            "home_network" => (if $c.home_gateway == null and ($c.home_ssid | is-empty) { $s.home_none } else {
                let wifi = if ($c.home_ssid | is-empty) { "" } else { text-fill $s.home_wifi {ssid: $c.home_ssid} }
                $"(text-fill $s.home_router {router: ($c.home_gateway | default $s.home_router_none)})($wifi)"
            })
            "disk" => (text-fill $s.disk {disk: $c.disk, model: $c.disk_model, encryption: (if $c.encrypt { $s.encrypted } else { $s.unencrypted })})
            "secure_boot" => (if $c.secure_boot == "off" { $s.secure_boot_off } else if $c.setup_mode { $c.secure_boot } else { $s.secure_boot_no_setup_mode })
            "root" => (if ($c.root_password | is-empty) { $s.root_locked } else { $s.root_set })
            "ssh_key" => (if ($c.ssh_key | is-not-empty) { $c.ssh_key | split row " " | first } else if $c.server { $s.ssh_key_none } else { null })
            _ => (error make {msg: $"($QUESTIONS): summary row ($row), not one bootstrap.nu fills"})
        }
        if $value == null { null } else { $"($label | fill --width $width)($value)" }
    } | compact | str join "\n"
}

def wsl-install [q: record, c: record]: nothing -> nothing {
    if ($c.user_password | is-empty) { die $q.messages.wsl_password_empty }
    if (tui) { ^clear }
    pacman-init
    user-setup ($c | merge {target_root: ""})
    $"($c.hostname)\n" | save --force /etc/hostname
    open --raw ($c.repo | path join configs base wsl wsl.conf) | str replace --all "@USER@" $c.username | str replace --all "@HOSTNAME@" $c.hostname | save --force /etc/wsl.conf
    log-info $q.messages.wsl_done
}

# Asks or reads every answer, then partitions, installs and arms the stage chain (or sets up WSL); root only.
export def bootstrap-run [repo: path, platform_arg: string]: nothing -> nothing {
    let q = questions-load
    let m = $q.messages
    if not (is-admin) { die $m.root }
    if not (on-archiso) and not (on-wsl) { die $m.host }
    $env.LOG_TAG = "bootstrap"
    let wsl = on-wsl
    mirrors-rank
    tui-init
    if (tui) { screen $m.welcome.title msgbox (if $wsl { $m.welcome.text_wsl } else { $m.welcome.text }) | ignore }

    let start = {
        repo: $repo platform_arg: $platform_arg host_wsl: $wsl machine_wsl: false platforms: (platform-names $repo)
        password_given: (env-or BOOTSTRAP_PASSWORD | is-not-empty) username: "" profile: $PROFILE_CUSTOM profile_file: ""
        capabilities: [] platform: "" generic: false server: false hostname: "" groups: [] form_factor: "" homelab: false
        home_network: false home_gateway: null home_ssid: "" target_root: $MOUNT password: ""
        user_password: (env-or BOOTSTRAP_USER_PASSWORD) root_password: (env-or BOOTSTRAP_ROOT_PASSWORD) options: {}
        ssh_key: "" disk: "" disk_model: "" setup_mode: false
    }
    mut c = questions-walk $q ($start | merge (question-defaults $q))
    if $c.machine_wsl {
        wsl-install $q $c
        return
    }

    let password = one-line (env-or BOOTSTRAP_PASSWORD) "password"
    let luks = if $c.encrypt { $c.password } else { "" }
    if ($c.user_password | is-empty) { $c.user_password = if $c.encrypt { $luks } else { $password } }
    if ($c.user_password | is-empty) { die (text-fill $m.password_missing $c) }

    let summary = summary-render $q $c
    let disk = $c.disk
    let capabilities = $c.capabilities
    if (tui) {
        dlg --title $q.summary.title --no-collapse --yes-label $q.summary.install --no-label $q.summary.quit --yesno $"($summary)\n\n(text-fill $q.summary.question $c)" (height $summary ($TUI_BOX_ROWS + 2)) ($TUI_WIDTH | into string) | ignore
        ^clear
    } else {
        print $summary
        if not (assume) and not (yes $q.summary.title (text-fill $q.summary.question $c)) { die $m.aborted }
    }
    $env.BOOTSTRAP_TUI = "0"

    let luks_pw = $luks
    let c = $c
    let parts = span partition {} {
        ^umount -R $MOUNT | complete | ignore
        ^cryptsetup close $LUKS_NAME | complete | ignore
        disk-release $disk
        let held = ^lsblk -lno MOUNTPOINTS $disk | lines | each { str trim } | where $it != ""
        if ($held | is-not-empty) { die $"($disk) is in use, mounted at ($held | str join ' ')" }
        ^lsblk -J -lnpo NAME,TYPE $disk | from json | get blockdevices | where type == part | each { ^wipefs -af $in.name } | ignore
        ^wipefs -af $disk
        ^sgdisk --zap-all $disk
        ^sgdisk -n $"1:0:+($ESP_SIZE_MIB)M" -t 1:ef00 -c 1:ESP $disk
        let per_4k = 4096 // (^blockdev --getss $disk | into int)
        let first = ^sgdisk -F $disk | into int
        let last = ^sgdisk -E $disk | into int
        let kind = if $c.encrypt { {type: $PART_TYPE_LUKS, name: cryptroot} } else { {type: $PART_TYPE_ROOT, name: root} }
        ^sgdisk -n $"2:($first):($first + ($last - $first + 1) // $per_4k * $per_4k - 1)" -t $"2:($kind.type)" -c $"2:($kind.name)" $disk
        ^partprobe $disk
        ^udevadm settle
        let parts = ^lsblk -J -lnpo NAME,TYPE $disk | from json | get blockdevices | where type == part | get name
        if ($parts | length) != 2 { die $"expected 2 partitions on ($disk) after partitioning, got ($parts | length)" }
        if $c.encrypt {
            $luks_pw | ^cryptsetup --batch-mode luksFormat ...$LUKS_FORMAT --key-file - $parts.1
            $luks_pw | ^cryptsetup open ...$LUKS_OPEN --key-file - $parts.1 $LUKS_NAME
        }
        let root = if $c.encrypt { $"/dev/mapper/($LUKS_NAME)" } else { $parts.1 }
        ^mkfs.fat -F 32 -n ESP $parts.0
        ^mkfs.btrfs -f -L arch $root
        ^mount $root $MOUNT
        for s in $SUBVOLS { ^btrfs subvolume create ($MOUNT | path join $s.name) }
        ^umount $MOUNT
        for s in $SUBVOLS {
            let at = $"($MOUNT)($s.mount)" | str trim --right --char "/"
            mkdir $at
            ^mount -o $"($BTRFS_OPTS),subvol=($s.name)" $root $at
        }
        mkdir $"($MOUNT)/boot"
        ^mount -o umask=0077 $parts.0 $"($MOUNT)/boot"
        {esp: $parts.0, root: $parts.1, uuid: (if $c.encrypt { ^cryptsetup luksUUID $parts.1 } else { ^blkid -p -s UUID -o value $parts.1 } | str trim)}
    }

    span pacstrap {} {
        for _ in 1..$SYNC_WAIT_S {
            let synced = (^timedatectl show -p NTPSynchronized --value | str trim) == "yes"
            if $synced and (^systemctl show -p ActiveState --value archlinux-keyring-wkd-sync.service | complete | get stdout | str trim) != "activating" { break }
            sleep 1sec
        }
        let ucode = if (open --raw /proc/cpuinfo | str contains GenuineIntel) { "intel-ucode" } else { "amd-ucode" }
        let base = $HOMELAB_MIRROR | split row '$' | first
        if $c.homelab and not (open --raw $MIRRORLIST | str contains $base) and (^curl -fs -m $PING_TIMEOUT_S -r 0-0 -o /dev/null $HOMELAB_MIRROR_PROBE | complete).exit_code == 0 {
            $"Server = ($HOMELAB_MIRROR)\n(open --raw $MIRRORLIST)" | save --force $MIRRORLIST
        }
        ^pacman -Sy --noconfirm --needed archlinux-keyring
        ^pacstrap -K $MOUNT ...$PACSTRAP $ucode
        if ($MIRROR_COUNTRIES | path exists) { ^install -Dm644 $MIRROR_COUNTRIES $"($MOUNT)($MIRROR_COUNTRIES)" }
        ^genfstab -U $MOUNT | save --append $"($MOUNT)/etc/fstab"
        if $c.encrypt {
            let key = $"($MOUNT)($STAGE_KEY_FILE)"
            mkdir ($key | path dirname)
            ^chmod 700 ($key | path dirname)
            ^head -c $STAGE_KEY_BYTES /dev/urandom | save --force --raw $key
            ^chmod 600 $key
            $luks_pw | ^cryptsetup luksAddKey --key-file - --pbkdf pbkdf2 --pbkdf-force-iterations 1000 $parts.root $key
            $"FILES+=\(($STAGE_KEY_FILE)\)\n" | save --force $"($MOUNT)/etc/mkinitcpio.conf.d/dotfiles-stage.conf"
        }
        target-system $c $parts.uuid
    }

    wifi-carry $c
    if $c.home_gateway != null { $"($c.home_gateway)\n" | save --force $"($MOUNT)($HOME_GATEWAYS)" }

    if "secrets" in $capabilities {
        if not (try { ^pacman -Sy --noconfirm --needed ...$SECRETS_TOOLS; true } catch { false }) { log-warn "secrets tools did not install, the config stage unlocks instead" }
        ^systemctl start pcscd.socket | complete | ignore
        let unlocked = try { with-env {DOTFILES: $repo, PROFILE_FILE: $c.profile_file} { ^nu --no-config-file ($repo | path join scripts dot.nu) secrets unlock }; true } catch { false }
        if not $unlocked { log-warn "secrets stay locked for now" }
    }
    user-setup $c
    stage-arm $c $parts.uuid
    boot-next-installed $parts.esp
    let log = env-or LSCK0_LOG
    if ($log | is-not-empty) and ($log | path exists) {
        ^install -Dm600 $log $"($MOUNT)($ISO_LOG_TARGET)"
    }
    ^umount -R $MOUNT
    if $c.encrypt { ^cryptsetup close $LUKS_NAME }
    log-info (text-fill $m.done {delay: $REBOOT_DELAY})
    sleep $REBOOT_DELAY
    ^reboot
}
