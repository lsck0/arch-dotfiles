# dot bootstrap, as root from the Arch ISO (or a fresh WSL distro): every question first, nothing written before the
# summary is confirmed; then the disk is erased and encrypted, the base system pacstrapped and the stage chain armed.
# a person at the console gets dialog screens; without a tty or with BOOTSTRAP_ASSUME_YES=1 plain prompts and env:
# BOOTSTRAP_{USERNAME,DISK,PASSWORD,USER_PASSWORD,ROOT_PASSWORD,KEYMAP}, for a new machine also
# BOOTSTRAP_{HOSTNAME,GROUPS,TIMEZONE,LOCALE} and BOOTSTRAP_HOME_NETWORK=0|1 (unasked and 0 under ASSUME_YES)

use log.nu *
use state.nu [SYSTEM_REPO path-kind]
use system.nu [system-pack system-unpack]

const MIRRORLIST = "/etc/pacman.d/mirrorlist"
# the ranked mirrors' countries, pacstrapped along for the installed system's monthly rebuild (configs/base/ghostmirror)
const MIRROR_COUNTRIES = "/etc/pacman.d/mirror-countries"
const MIRROR_CANDIDATES = 20
const MIRROR_KEEP = 10
# fewer rated servers and the ranking failed: the country alone is retried worldwide, then the iso's list stays
const MIRROR_RANKED_MIN = 5
const MIRROR_AGE_H = 12
const MIRROR_DOWNLOAD_TIMEOUT_S = 5
const REFLECTOR_WAIT_S = 90
const GEO_TIMEOUT_S = 3
const HOMELAB_MIRROR = 'http://10.100.0.104:8090/archlinux/$repo/os/$arch'
const HOMELAB_MIRROR_PROBE = "http://10.100.0.104:8090/archlinux/core/os/x86_64/core.db"

const KEYMAP_DEFAULT = "de-latin1"
const TIMEZONE_DEFAULT = "Europe/Berlin"
const LOCALE_DEFAULT = "en_US.UTF-8"
const ESP_SIZE_MIB = 1024
const LUKS_NAME = "root"
const MOUNT = "/mnt"
const BTRFS_OPTS = "noatime,compress=zstd"
# vm disks, models and docker's data top level, out of @: a timeshift snapshot would pin them and a rollback revert them
const SUBVOLS = [
    [name mount]; ["@" "/"] ["@home" "/home"] ["@log" "/var/log"] ["@pkg" "/var/cache/pacman/pkg"]
    ["@libvirt" "/var/lib/libvirt/images"] ["@ollama" "/var/lib/ollama"] ["@docker" "/var/lib/docker"]
]
const LUKS_FORMAT = [--type luks2 --cipher aes-xts-plain64 --key-size 512 --sector-size 4096 --pbkdf argon2id]
const LUKS_OPEN = [--allow-discards --perf-no_read_workqueue --perf-no_write_workqueue --persistent]
const PACSTRAP = [base linux linux-firmware mkinitcpio btrfs-progs cryptsetup binutils networkmanager sudo git zsh zram-generator libfido2 nushell]
const HOOKS = "HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)"
const CMDLINE_TAIL = "rw zswap.enabled=0 nmi_watchdog=0 slab_nomerge init_on_alloc=1 init_on_free=1 randomize_kstack_offset=on vsyscall=none page_alloc.shuffle=1"
const SECRETS_TOOLS = [age age-plugin-yubikey git-crypt pcsclite ccid libfido2 yubikey-manager]
const STAGE_STATE_DIR = "/var/lib/dotfiles-stage"
const STAGE_KEY_FILE = "/etc/cryptsetup-keys.d/root.key"
const STAGE_KEY_BYTES = 64
const SETUP_MODE_VAR = "/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"
const REBOOT_DELAY = 10sec
const SYNC_WAIT_S = 120
const NETWORK_TIMEOUT_S = 10
const PING_TIMEOUT_S = 2
const PLATFORM_LOCAL = "/etc/dotfiles/platform.nuon"
const PLATFORM_NEW = "new"
const LOGIN_SHELL = "/usr/bin/zsh"
# the networkmanager module's home rule: a link is home while its default gateway's mac is listed here
const HOME_GATEWAYS = "/etc/NetworkManager/home-gateways"
const USERNAME_PATTERN = '^[a-z_][a-z0-9_-]{0,31}$'
const HOSTNAME_PATTERN = '^[A-Za-z0-9][A-Za-z0-9-]{0,62}$'
const KEYMAP_PATTERN = '^[A-Za-z0-9_-]+$'
const TIMEZONE_PATTERN = '^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+){0,2}$'
const MAC_PATTERN = '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'
const TUI_WIDTH = 72
# rows around the text: frame and buttons, an inputbox's field on top; dialog's own auto height drops wrapped text
const TUI_BOX_ROWS = 4
const TUI_INPUT_ROWS = 7
const TUI_TEXT_MARGIN = 6
const TUI_BACKTITLE = "arch-dotfiles bootstrap"
# console keymaps systemd's kbd-model-map turns into an x11 layout, so the desktop follows too
const COMMON_KEYMAPS = [
    de-latin1 German us "English (US)" uk "English (UK)" fr-latin1 French es Spanish it Italian pl2 Polish
    sv-latin1 Swedish dk Danish no Norwegian fi Finnish pt-latin1 Portuguese br-abnt2 Brazilian be-latin1 Belgian
    sg-latin1 "Swiss German" dvorak "US Dvorak"
]
const REQUIRED_GROUP = "base"
const GROUP_DESCRIPTIONS = {
    base: "kernel, boot, drivers, firewall, security and system services"
    core: "shell, cli tools, diagnostics, git, gpg, theming"
    creating: "image, audio, video and 3d editors, obs"
    desktop: "hyprland and plasma, browsers, terminals, audio, printing, apps"
    fonts: "noto, nerd and cjk fonts"
    gaming: "steam, lutris, heroic, proton and game tooling"
    latex: "tex engine, pdf viewer, zotero"
    llm: "local language models with ollama"
    pentesting: "security auditing and pentest tools"
    programming: "compilers, editors, language servers, docker"
    qemu: "virtual machines, waydroid, distrobox"
    rocm: "amd gpu compute (ollama, pytorch), amd only"
    socials: "discord, signal, telegram, spotify"
}

def assume []: nothing -> bool { $env.BOOTSTRAP_ASSUME_YES? == "1" }
def tui []: nothing -> bool { $env.BOOTSTRAP_TUI? == "1" }
def env-or [name: string]: nothing -> string { $env | get --optional $name | default "" }

def die [message: string] {
    # a leftover dialog screen would hide the reason
    if (tui) { ^clear }
    error make {msg: $message}
}

def online []: nothing -> bool {
    (^curl -fsI -m $NETWORK_TIMEOUT_S https://archlinux.org | complete).exit_code == 0
}

def --env tui-init []: nothing -> nothing {
    if (assume) or ($env.TERM? | default dumb) == "dumb" or not (^test -t 0 | complete).exit_code == 0 { return }
    if (which dialog | is-empty) and not ((online) and (^pacman -Sy --noconfirm --needed dialog | complete).exit_code == 0) {
        log-warn "dialog unavailable, using plain prompts"
        return
    }
    $env.BOOTSTRAP_TUI = "1"
}

def --wrapped dlg [...args: string]: nothing -> string {
    try { ^dialog --backtitle $TUI_BACKTITLE --cr-wrap --stdout ...$args } catch { die aborted }
}

def height [text: string, rows: int]: nothing -> string {
    ($text | ^fold -s -w ($TUI_WIDTH - $TUI_TEXT_MARGIN) | lines | length) + $rows | into string
}

# screen <title> <inputbox|passwordbox|msgbox> <text> [init]: one dialog box sized to its wrapped text
def screen [title: string, kind: string, text: string, ...init: string]: nothing -> string {
    let rows = if $kind in [inputbox passwordbox] { $TUI_INPUT_ROWS } else { $TUI_BOX_ROWS }
    let extra = if $kind == "passwordbox" { [--insecure] } else { [] }
    dlg --title $title --no-collapse ...$extra $"--($kind)" $text (height $text $rows) ($TUI_WIDTH | into string) ...$init
}

# ask <check> <label> <text> <default>: an answer <check> accepts; the default as is unattended
def ask [check: closure, label: string, text: string, default: string]: nothing -> any {
    if (assume) { return $default }
    mut note = ""
    loop {
        let answer = if (tui) { screen $label inputbox $"($note)($text)" $default } else { input $"($label) [($default)]: " | if ($in | is-empty) { $default } else { $in } }
        if (do $check $answer) { return $answer }
        $note = $"'($answer)' is not valid, try again.\n\n"
        if not (tui) { log-warn $note }
    }
}

def menu [title: string, text: string, default: string, items: list<string>]: nothing -> string {
    dlg --title $title --default-item $default --menu $text "0" ($TUI_WIDTH | into string) "0" ...$items
}

def yes [title: string, text: string]: nothing -> bool {
    if (tui) {
        let status = (^dialog --backtitle $TUI_BACKTITLE --cr-wrap --title $title --defaultno --yesno $text (height $text $TUI_BOX_ROWS) ($TUI_WIDTH | into string) | complete).exit_code
        # yes 0, no 1, esc quits like every other screen
        if $status > 1 { die aborted }
        $status == 0
    } else {
        (input $"($text) [y/N] ") == "y"
    }
}

def keymap-load [keymap: string]: nothing -> bool {
    $keymap =~ $KEYMAP_PATTERN and (^loadkeys $keymap | complete).exit_code == 0
}

def ask-keymap []: nothing -> string {
    if not (tui) { return (ask {|k| keymap-load $k } keymap "" $KEYMAP_DEFAULT) }
    let picked = menu keyboard "Keyboard layout (console, boot password prompt, desktop). Applies now." $KEYMAP_DEFAULT ($COMMON_KEYMAPS ++ [other "type another console keymap"])
    if $picked != "other" { return $picked }
    ask {|k| keymap-load $k } keymap "Console keymap name, as in /usr/share/kbd/keymaps, e.g. cz, hu, ru, trq:" ""
}

# ask-password <label> <hint> <empty_ok>: typed twice; empty only when the caller has a default for it
def ask-password [label: string, hint: string, empty_ok: bool]: nothing -> any {
    mut note = ""
    loop {
        let first = if (tui) { screen $label passwordbox $"($note)($hint)" } else { print -e $hint; input -s $"($label): " }
        if ($first | is-empty) {
            if $empty_ok { return "" }
            $note = "It must not be empty.\n\n"
            if not (tui) { die $"empty ($label)" }
            continue
        }
        let second = if (tui) { screen $label passwordbox "The same again:" } else { print -e ""; input -s "again: " }
        if not (tui) { print -e "" }
        if $first == $second { return $first }
        if not (tui) { die "passwords differ" }
        $note = "The two did not match, once more.\n\n"
    }
}

def --wrapped in-target [root: string, ...cmd: string]: nothing -> nothing {
    if ($root | is-empty) { ^($cmd | first) ...($cmd | skip 1) } else { ^arch-chroot $root ...$cmd }
}

# a GKeyFile string, as NetworkManager's keyfiles read it
def keyfile-escape [value: string]: nothing -> string {
    $value | str replace --all '\' '\\' | str replace --all "\n" '\n' | str replace --all "\t" '\t' | str replace --all "\r" '\r'
    | str replace --regex '^ ' '\s'
}

def default-route []: nothing -> record {
    ^ip -j -4 route show default | from json | get --optional 0 | default {}
}

# the mac of the router this live system routes through, lowercase; null without one
def home-gateway-mac []: nothing -> any {
    let route = default-route
    if ($route.gateway? | is-empty) or ($route.dev? | is-empty) { return null }
    # the neighbour cache may not hold the router yet
    ^ping -c 1 -W $PING_TIMEOUT_S -I $route.dev $route.gateway | complete | ignore
    let mac = ^ip -j neigh show $route.gateway dev $route.dev | from json | get --optional 0.lladdr | default "" | str lowercase
    if $mac =~ $MAC_PATTERN { $mac } else { null }
}

def home-ssid []: nothing -> string {
    let dev = default-route | get --optional dev | default ""
    if ($dev | is-empty) or (which iw | is-empty) { return "" }
    ^iw dev $dev link | complete | get stdout | lines | parse --regex '^\s*SSID: (?<ssid>.*)$' | get --optional 0.ssid | default ""
}

# the fastest https mirrors by measured download rate, before anything big downloads; the iso's list is a cdn that can
# crawl, older isos rate a worldwide --latest 20 at boot
def mirrors-rank []: nothing -> nothing {
    if not ("/run/archiso" | path exists) or (which reflector | is-empty) { return }
    # older isos run reflector.service with Restart=on-failure: let a rating finish, then stop any retry
    for _ in 1..$REFLECTOR_WAIT_S {
        if (^systemctl show -p ActiveState --value reflector.service | complete | get stdout | str trim) != "activating" { break }
        sleep 1sec
    }
    ^systemctl stop reflector.service | complete | ignore
    let country = try { ^curl -fsS -m $GEO_TIMEOUT_S https://www.cloudflare.com/cdn-cgi/trace | lines | parse "loc={loc}" | get 0.loc } catch { "" }
    log-info $"ranking mirrors by download rate(if ($country | is-empty) { '' } else { $' in ($country)' })"
    let tmp = mktemp --directory
    let ranked = [$country worldwide] | where $it != "" | each {|scope|
        let where = if $scope == "worldwide" { [] } else { [--country $scope] }
        let run = ^reflector --verbose --protocol https --age $MIRROR_AGE_H --latest $MIRROR_CANDIDATES --fastest $MIRROR_KEEP --connection-timeout $GEO_TIMEOUT_S --download-timeout $MIRROR_DOWNLOAD_TIMEOUT_S ...$where --save ($tmp | path join list) | complete
        if $run.exit_code != 0 { return null }
        # --verbose logs every rate, a failed one as 0.00
        let rates = $run.stderr | lines | parse --regex '(?<url>\S+)\s+(?<rate>[\d.]+) KiB/s' | where {|r| ($r.rate | into float) > 0 }
        let servers = open --raw ($tmp | path join list) | lines | where ($it | str starts-with "Server") | each {|line|
            let url = $line | split row " " | last | str replace '$repo/os/$arch' ""
            $rates | where url == $url | get --optional 0 | if $in == null { null } else { {server: $line, rate: ($in.rate | into float)} }
        } | compact
        {scope: $scope, servers: $servers}
    } | compact | where ($it.servers | length) >= $MIRROR_RANKED_MIN | get --optional 0
    rm --recursive --force $tmp
    if $ranked == null {
        log-warn "mirror ranking failed, keeping the iso's list"
        return
    }
    let fallback = open --raw $MIRRORLIST | lines | where ($it | str starts-with "Server") and $it not-in $ranked.servers.server
    [$"# ranked by dot bootstrap (date now | format date '%F'): the fastest https mirrors \(($ranked.scope)\) by download rate"]
    | append $ranked.servers.server | append ["" "# the list before ranking, the fallback"] | append $fallback
    | str join "\n" | $"($in)\n" | save --force $MIRRORLIST
    let urls = $ranked.servers.server | each { split row " " | last }
    let countries = ^reflector --info --protocol https | complete | get stdout | lines | window 2 | where {|w| ($w.0 | str starts-with "https:") }
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

# the login user with its password, wheel and zsh, root locked unless given one, the verified repo at home and as the
# root copy, the machine's and the user's facts
def user-setup [c: record]: nothing -> nothing {
    let root = $c.target_root
    let home = $"($root)/home/($c.username)"
    let repo_copy = $home | path join projects arch-dotfiles
    if not (in-target-ok $root id -u $c.username) {
        in-target $root useradd -m -G wheel -s $LOGIN_SHELL $c.username
    }
    $"($c.username):($c.user_password)\n" | in-target-input $root chpasswd
    in-target $root passwd -l root
    if ($c.root_password | is-not-empty) { $"root:($c.root_password)\n" | in-target-input $root chpasswd }
    # sudo skips a drop-in named with a dot, so this one is checked before it can lock anyone out
    let sudoers = $"($root)/etc/sudoers.d/10-wheel"
    ^install -Dm440 ($c.repo | path join configs base sudo 10-wheel) $"($sudoers).new"
    if not (in-target-ok $root visudo -cqf /etc/sudoers.d/10-wheel.new) { die "the wheel sudoers drop-in does not parse" }
    mv --force $"($sudoers).new" $sudoers
    # a rerun under wsl keeps the checkout and whatever work is in it
    if not ($repo_copy | path exists) {
        mkdir ($repo_copy | path dirname)
        ^cp -a $c.repo $repo_copy
    }
    let local = $"($root)($PLATFORM_LOCAL)"
    if $c.platform == $PLATFORM_NEW {
        mkdir ($local | path dirname)
        {hostname: $c.hostname, groups: $c.groups} | to nuon | save --force $local
    } else {
        # the platform file prefers the machine's own answers, so a rerun's earlier ones must not outlive this choice
        rm --force $local
    }
    let profile = $home | path join .config dotfiles profile.nuon
    if ($c.profile_file | path exists) and not ($profile | path exists) { ^install -Dm644 $c.profile_file $profile }
    # the system layer only ever runs from this root-owned copy of the verified clone
    try { system-pack $c.repo | system-unpack $"($root)($SYSTEM_REPO)" (^git -C $c.repo rev-parse HEAD | str trim) } catch {|e| die $"cannot seed the root copy ($root)($SYSTEM_REPO): ($e.msg)" }
    in-target $root chown -R $"($c.username):($c.username)" $"/home/($c.username)"
}

def --wrapped in-target-ok [root: string, ...cmd: string]: nothing -> bool {
    (try { in-target $root ...$cmd; true } catch { false })
}

def --wrapped in-target-input [root: string, ...cmd: string]: string -> nothing {
    let text = $in
    if ($root | is-empty) { $text | ^($cmd | first) ...($cmd | skip 1) } else { $text | ^arch-chroot $root ...$cmd }
}

def pacman-init []: nothing -> nothing {
    ^pacman-key --init
    ^pacman-key --populate archlinux
    ^pacman -Syu --noconfirm --needed git gnupg sudo zsh nushell
}

# the iwd wifi the ISO connected with, as NetworkManager keyfiles, so the chained boots come up online
def wifi-carry [c: record]: nothing -> nothing {
    for psk in (glob /var/lib/iwd/*.psk) {
        let name = $psk | path parse | get stem
        # iwd names an ssid that is not path-safe =<hex>
        let ssid = if ($name | str starts-with "=") { $name | str substring 1.. | decode hex | decode utf-8 } else { $name }
        let passphrase = open --raw $psk | lines | parse "Passphrase={p}" | get --optional 0.p | default ""
        if ($passphrase | is-empty) { continue }
        # the home rule needs the hardware mac there, every other wifi gets NetworkManager.conf's random one
        let mac = if $c.home_gateway != null and $ssid == $c.home_ssid { "\ncloned-mac-address=permanent" } else { "" }
        let bytes = $ssid | encode utf-8 | chunks 1 | each { $"(into int);" } | str join
        let file = $"($MOUNT)/etc/NetworkManager/system-connections/($name).nmconnection"
        mkdir ($file | path dirname)
        [
            "[connection]" $"id=(keyfile-escape $ssid)" "type=wifi" "" "[wifi]" $"ssid=($bytes)($mac)" "" "[wifi-security]"
            "key-mgmt=wpa-psk" $"psk=(keyfile-escape $passphrase)" "" "[ipv4]" "method=auto" "" "[ipv6]" "method=auto"
        ] | str join "\n" | $"($in)\n" | save --force $file
        ^chmod 600 $file
    }
}

def target-system [c: record, luks_uuid: string]: nothing -> nothing {
    let t = {|path| $"($MOUNT)($path)" }
    ^ln -sf $"/usr/share/zoneinfo/($c.timezone)" (do $t /etc/localtime)
    in-target $MOUNT hwclock --systohc
    open --raw (do $t /etc/locale.gen) | str replace --regex --multiline $"^#\(($c.locale) \)" '$1' | save --force (do $t /etc/locale.gen)
    in-target $MOUNT locale-gen
    $"LANG=($c.locale)\n" | save --force (do $t /etc/locale.conf)
    $"KEYMAP=($c.keymap)\n" | save --force (do $t /etc/vconsole.conf)
    $"($c.hostname)\n" | save --force (do $t /etc/hostname)
    $"127.0.0.1 localhost\n::1 localhost\n127.0.1.1 ($c.hostname)\n" | save --force (do $t /etc/hosts)
    mkdir (do $t /etc/kernel)
    # the ukis (configs/base/boot) embed this file as their only cmdline
    $"rd.luks.name=($luks_uuid)=($LUKS_NAME) root=/dev/mapper/($LUKS_NAME) rootflags=subvol=@ ($CMDLINE_TAIL)\n" | save --force (do $t /etc/kernel/cmdline)
    # systemd initramfs: sd-vconsole so the LUKS prompt uses the right keymap
    open --raw (do $t /etc/mkinitcpio.conf) | str replace --regex --multiline '^HOOKS=.*$' $HOOKS | save --force (do $t /etc/mkinitcpio.conf)
    # one uki per kernel from /etc/kernel/cmdline, the preset configs/base/boot/boot.nu's boot-commit keeps; systemd-boot
    # finds it in /EFI/Linux without an entry
    for preset in (glob (do $t /etc/mkinitcpio.d/*.preset)) {
        let pkgbase = $preset | path parse | get stem
        open --raw $preset | lines | where not ($it =~ '^#?default_(image|uki|cmdline)=') | each { str replace --regex '^PRESETS=.*' "PRESETS=('default')" }
        | append [$"default_uki=\"/boot/EFI/Linux/arch-($pkgbase).efi\"" 'default_cmdline="/etc/kernel/cmdline"'] | str join "\n" | $"($in)\n" | save --force $preset
        # pacstrap's plain image, built before the uki preset
        rm --force (do $t $"/boot/initramfs-($pkgbase).img") (do $t $"/boot/initramfs-($pkgbase)-fallback.img")
    }
    mkdir (do $t /boot/EFI/Linux)
    in-target $MOUNT mkinitcpio -P
    in-target $MOUNT systemctl enable NetworkManager.service NetworkManager-wait-online.service systemd-timesyncd.service
    # unsigned for the Setup Mode stage boots, which need no menu; the config stage replaces the loader.conf and signs.
    # --variables=yes: bootctl may skip the firmware's boot order in a chroot
    in-target $MOUNT bootctl install --esp-path=/boot --variables=yes
    # zram swap from the first boot, install compiles for hours before config would link it
    ^install -Dm644 ($c.repo | path join configs base zram zram-generator.conf) (do $t /etc/systemd/zram-generator.conf)
}

def stage-arm [c: record, luks_uuid: string]: nothing -> nothing {
    let state = $"($MOUNT)($STAGE_STATE_DIR)"
    mkdir $state
    "install\n" | save --force ($state | path join next)
    $"/dev/disk/by-uuid/($luks_uuid)\n" | save --force ($state | path join luks-device)
    # verifypw=any: with %wheel still asking, `sudo -v` would want a password despite the NOPASSWD rule
    $"($c.username) ALL=\(ALL:ALL\) NOPASSWD: ALL\nDefaults:($c.username) verifypw=any\n" | save --force $"($MOUNT)/etc/sudoers.d/zz-dotfiles-stage"
    ^chmod 440 $"($MOUNT)/etc/sudoers.d/zz-dotfiles-stage"
    let checkout = $"/home/($c.username)/projects/arch-dotfiles"
    # PAMName gives the stages a logind session, so user units and dbus work like after a login. not oneshot:
    # multi-user.target would wait for the whole stage, and a link restarting a unit ordered after it (tlp) deadlocks.
    # a tty, not journal+console, so dot re-execs under script and pacman draws its bars
    [
        "[Unit]" "Description=arch-dotfiles install chain (dot stage)" "Wants=network-online.target"
        "After=network-online.target" $"ConditionPathExists=($STAGE_STATE_DIR)/next" "" "[Service]" "Type=exec"
        $"User=($c.username)" "PAMName=login" $"WorkingDirectory=($checkout)"
        $"ExecStart=/usr/bin/nu --no-config-file ($checkout)/scripts/dot.nu stage" "StandardOutput=tty"
        "TimeoutStartSec=infinity" "" "[Install]" "WantedBy=multi-user.target"
    ] | str join "\n" | $"($in)\n" | save --force $"($MOUNT)/etc/systemd/system/dotfiles-stage.service"
    in-target $MOUNT systemctl enable dotfiles-stage.service
}

export def bootstrap-run [repo: path, platform_arg: string]: nothing -> nothing {
    if not (is-admin) { die "run as root" }
    $env.LOG_TAG = "bootstrap"
    let wsl = (^systemd-detect-virt | complete | get stdout | str trim) == "wsl"
    mirrors-rank
    tui-init
    let welcome = if $wsl {
        "WSL setup: a user with sudo, the checkout, wsl.conf. Then restart the distro and run dot update.\n\nEsc or Cancel quits."
    } else {
        "Installs Arch Linux with the arch-dotfiles. Questions first (nothing written until you confirm), then the chosen disk is ERASED and encrypted, then unattended reboots while it installs (can take hours; stay plugged in and online).\n\nEsc or Cancel quits."
    }
    if (tui) { screen welcome msgbox $welcome | ignore }

    # the layout first: every later answer and password is typed on it
    let keymap = if $wsl { $KEYMAP_DEFAULT } else { env-or BOOTSTRAP_KEYMAP | if ($in | is-empty) { ask-keymap } else { $in } }
    if not $wsl and not (keymap-load $keymap) { die $"unknown keymap '($keymap)'" }

    let profiles = glob ($repo | path join profiles *.nuon) | where not ($it | str ends-with ".options.nuon") | each { path parse | get stem }
    let username = env-or BOOTSTRAP_USERNAME | if ($in | is-empty) {
        ask {|u| $u =~ $USERNAME_PATTERN } username $"Your login name. A name with a profile \(($profiles | str join ' ' | default none)\) gets that profile's secrets/identity/homelab; any other name is a guest \(same desktop and tools, no personal parts\)." ($profiles | get --optional 0 | default "")
    } else { $in }
    if $username !~ $USERNAME_PATTERN { die $"invalid username '($username)', expected ($USERNAME_PATTERN)" }
    let profile_nuon = $repo | path join profiles $"($username).nuon"
    let capabilities = if ($profile_nuon | path exists) { open $profile_nuon | get capabilities } else { [] }

    let platforms = glob ($repo | path join platforms *.nuon) | where not ($it | str ends-with ".options.nuon") | each { path parse | get stem }
    let platform = if ($platform_arg | is-not-empty) { $platform_arg } else if (assume) { $PLATFORM_NEW } else if (tui) {
        let items = $platforms | each {|p| [$p (open ($repo | path join platforms $"($p).nuon") | get form_factor)] } | flatten
        menu machine "Which machine is this?" $PLATFORM_NEW ($items ++ [$PLATFORM_NEW "any other machine: a few questions"])
    } else {
        print $"platforms: ($platforms | str join ' ') ($PLATFORM_NEW)"
        input $"platform [($PLATFORM_NEW)]: " | if ($in | is-empty) { $PLATFORM_NEW } else { $in }
    }

    mut c = {
        repo: $repo username: $username platform: $platform keymap: $keymap timezone: $TIMEZONE_DEFAULT
        locale: $LOCALE_DEFAULT hostname: "" groups: [] form_factor: "" homelab: false home_gateway: null
        home_ssid: "" target_root: $MOUNT profile_file: ($repo | path join profiles $"($username).nuon")
        user_password: "" root_password: ""
    }
    if $platform != $PLATFORM_NEW {
        let file = $repo | path join platforms $"($platform).nuon"
        if not ($file | path exists) { die $"unknown platform '($platform)', one of: ($platforms | str join ' ') ($PLATFORM_NEW)" }
        let p = open $file
        if ($p.hostname? | is-empty) { die $"($file) sets no hostname" }
        let all = ls ($repo | path join configs) | where type == dir | get name | path basename
        $c = $c | merge {hostname: $p.hostname, groups: ($p.groups? | default $all), form_factor: ($p.form_factor? | default ""), homelab: ($p.facts?.homelab? | default false)}
    } else {
        if $wsl { $c.form_factor = "wsl" }
        let hostname = env-or BOOTSTRAP_HOSTNAME | if ($in | is-empty) {
            ask {|h| $h =~ $HOSTNAME_PATTERN and $h not-in $platforms } hostname $"The machine's name on the network: letters, digits and dashes, none of ($platforms | str join ' ')." $"($username)-pc"
        } else { $in }
        if $hostname !~ $HOSTNAME_PATTERN or $hostname in $platforms { die $"invalid hostname '($hostname)', expected ($HOSTNAME_PATTERN) and none of: ($platforms | str join ' ')" }
        $c.hostname = $hostname
        if not $wsl {
            let timezone = env-or BOOTSTRAP_TIMEZONE | if ($in | is-empty) {
                ask {|z| $z =~ $TIMEZONE_PATTERN and ($"/usr/share/zoneinfo/($z)" | path exists) } timezone "Region/City, e.g. Europe/London. Later follows your location on its own." $TIMEZONE_DEFAULT
            } else { $in }
            if not ($timezone =~ $TIMEZONE_PATTERN and ($"/usr/share/zoneinfo/($timezone)" | path exists)) { die $"unknown timezone '($timezone)'" }
            # the iso's locale.gen lists every locale the installed glibc can generate
            let known = open --raw /etc/locale.gen | lines | each { str replace --regex '^#' '' | split row " " | first }
            let locale = env-or BOOTSTRAP_LOCALE | if ($in | is-empty) {
                ask {|l| $l in $known } locale "Language and formats, e.g. en_US.UTF-8, de_DE.UTF-8." $LOCALE_DEFAULT
            } else { $in }
            if $locale not-in $known { die $"unknown locale '($locale)'" }
            # asked once, while still on that network: its router's mac is what the installed machine recognises home by
            let home = env-or BOOTSTRAP_HOME_NETWORK | if ($in | is-not-empty) { $in } else if (assume) { "0" } else {
                if (yes "home network" "Is the network you are on now your home network?\n\nYes remembers its router as home: there this machine finds printers and other devices on its own (mDNS) and keeps its real network address. Every other network stays locked down.\n\nNo locks down every network, this one included.") { "1" } else { "0" }
            }
            if $home not-in ["0" "1"] { die $"BOOTSTRAP_HOME_NETWORK is '($home)', expected 0 or 1" }
            let gateway = if $home == "1" { home-gateway-mac } else { null }
            if $home == "1" and $gateway == null { log-warn "no router mac found, every network stays foreign" }
            $c = $c | merge {timezone: $timezone, locale: $locale, home_gateway: $gateway, home_ssid: (if $home == "1" { home-ssid } else { "" })}
        }
        let universe = ls ($repo | path join configs) | where type == dir | get name | path basename | sort
        let chosen = if (env-or BOOTSTRAP_GROUPS | is-not-empty) {
            env-or BOOTSTRAP_GROUPS | split row --regex '\s+' | where $it != ""
        } else if (assume) { $universe } else if (tui) {
            let items = $universe | where $it != $REQUIRED_GROUP | each {|g| [$g ($GROUP_DESCRIPTIONS | get --optional $g | default "") on] } | flatten
            dlg --title "package groups" --separate-output --checklist $"Space toggles, Enter accepts. '($REQUIRED_GROUP)' \(($GROUP_DESCRIPTIONS | get $REQUIRED_GROUP)\) is always installed." "0" ($TUI_WIDTH | into string) "0" ...$items | lines
        } else {
            print -e $"package groups \(($REQUIRED_GROUP) always\):"
            $universe | enumerate | each { print -e $"  ($in.index + 1)  ($in.item)" } | ignore
            let excludes = input "numbers to EXCLUDE (space-separated), enter for all: " | split row " " | where $it != ""
            $universe | enumerate | where {|g| ($g.index + 1 | into string) not-in $excludes } | get item
        }
        # before anything is erased: only discovered groups, base always
        let groups = [$REQUIRED_GROUP] ++ ($chosen | where $it != $REQUIRED_GROUP)
        let unknown = $groups | where $it not-in $universe
        if ($unknown | is-not-empty) { die $"unknown package group '($unknown | first)', one of: ($universe | str join ' ')" }
        $c.groups = $groups
    }

    if $c.form_factor == "wsl" {
        if not $wsl { die $"($platform) is a wsl platform, run it in the distro's root shell" }
        let password = env-or BOOTSTRAP_USER_PASSWORD | if ($in | is-empty) { ask-password $"($username) password" "For login and sudo." false } else { $in }
        if ($password | is-empty) { die "empty password" }
        if (tui) { ^clear }
        pacman-init
        user-setup ($c | merge {target_root: "", user_password: $password, root_password: (env-or BOOTSTRAP_ROOT_PASSWORD)})
        $"($c.hostname)\n" | save --force /etc/hostname
        open --raw ($repo | path join configs base wsl wsl.conf) | str replace --all "@USER@" $username | str replace --all "@HOSTNAME@" $c.hostname | save --force /etc/wsl.conf
        log-info $"done. from windows: wsl --terminate archlinux, reopen it \(now ($username) with systemd\), then: cd ~/projects/arch-dotfiles && dot update"
        return
    }

    if not ("/run/archiso" | path exists) { die "not running from the Arch ISO" }
    if not ("/sys/firmware/efi" | path exists) { die "not booted in UEFI mode" }
    if not (online) { die "no network" }
    let setup_mode = (try { open --raw $SETUP_MODE_VAR | into binary | last 1 | into int } catch { 0 }) == 1
    if not $setup_mode and not (assume) and not (yes "secure boot" "Firmware not in Secure Boot Setup Mode, so install cannot enroll keys. Continue without Secure Boot? (To use it: quit, clear the keys / enable Setup Mode in firmware, rerun.)") {
        die "enable Setup Mode in the firmware, then rerun"
    }

    let disks = ^lsblk -J -dnpo NAME,TYPE,RM | from json | get blockdevices | where type == disk and rm == false and not ($it.name =~ 'zram|loop') | get name
    let label = {|d| ^lsblk -dno SIZE,MODEL $d | str trim | str replace --all --regex '\s+' ' ' }
    let disk = env-or BOOTSTRAP_DISK | if ($in | is-not-empty) { $in } else if ($disks | is-empty) {
        die "no disk found (set BOOTSTRAP_DISK)"
    } else if ($disks | length) == 1 { $disks.0 } else if (tui) {
        menu disk "Which disk gets erased and installed to?" $disks.0 ($disks | each {|d| [$d (do $label $d)] } | flatten)
    } else {
        ^lsblk -dpo NAME,SIZE,MODEL ...$disks
        input $"disk to erase \(($disks | str join ' ')\): "
    }
    if (path-kind $disk) == "" or (^test -b $disk | complete).exit_code != 0 { die $"($disk) is not a block device" }
    let layout = ^lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL $disk
    let erase = $"ERASE ALL DATA on ($disk)? type the device path to confirm:"
    let typed = if (assume) { $disk } else if (tui) { screen $"erase ($disk)" inputbox $"($layout)\n\n($erase)" } else { print $layout; input $"($erase) " }
    if $typed != $disk { die aborted }

    # unattended: BOOTSTRAP_PASSWORD is the LUKS one and nothing is asked; the user's defaults to it, root stays locked
    mut luks = env-or BOOTSTRAP_PASSWORD
    $c.user_password = env-or BOOTSTRAP_USER_PASSWORD
    $c.root_password = env-or BOOTSTRAP_ROOT_PASSWORD
    if ($luks | is-empty) {
        $luks = ask-password "LUKS password" $"Disk encryption password, asked at every boot on the ($keymap) layout." false
        if ($c.user_password | is-empty) { $c.user_password = ask-password $"($username) password [LUKS password]" "For login and sudo; empty uses the LUKS password." true }
        if ($c.root_password | is-empty) { $c.root_password = ask-password "root password [locked]" "Empty keeps root locked (sudo still works; no emergency shell)." true }
    }
    if ($c.user_password | is-empty) { $c.user_password = $luks }

    let summary = [
        $"user         ($username) (if ($profile_nuon | path exists) { $'\(profile: ($capabilities | str join ' ' | default none)\)' } else { '(guest)' })"
        $"machine      ($platform)" $"hostname     ($c.hostname)" $"keyboard     ($keymap)" $"timezone     ($c.timezone)"
        $"locale       ($c.locale)" $"groups       ($c.groups | str join ' ')"
        $"home network (if $c.home_gateway == null and ($c.home_ssid | is-empty) { 'no, every network locked down' } else { $'router ($c.home_gateway | default "not found")(if ($c.home_ssid | is-empty) { "" } else { $", wifi ($c.home_ssid)" })' })"
        $"disk         ($disk) (do $label $disk), erased"
        $"secure boot  (if $setup_mode { 'keys get enrolled' } else { 'skipped, not in Setup Mode' })"
        $"root         (if ($c.root_password | is-empty) { 'locked' } else { 'own password' })"
    ] | str join "\n"
    if (tui) {
        dlg --title summary --no-collapse --yes-label install --no-label quit --yesno $"($summary)\n\nInstall now? This erases ($disk)." (height $summary ($TUI_BOX_ROWS + 2)) ($TUI_WIDTH | into string) | ignore
        ^clear
    } else { print $summary }
    $env.BOOTSTRAP_TUI = "0"

    let luks_pw = $luks
    let c = $c
    let parts = span partition {} {
        ^umount -R $MOUNT | complete | ignore
        ^cryptsetup close $LUKS_NAME | complete | ignore
        ^wipefs -af $disk
        ^sgdisk --zap-all $disk
        ^sgdisk -n $"1:0:+($ESP_SIZE_MIB)M" -t 1:ef00 -c 1:ESP $disk
        # LUKS with 4096-byte sectors needs the partition size in whole 4 KiB, the free space rarely is
        let per_4k = 4096 // (^blockdev --getss $disk | into int)
        let first = ^sgdisk -F $disk | into int
        let last = ^sgdisk -E $disk | into int
        ^sgdisk -n $"2:($first):($first + ($last - $first + 1) // $per_4k * $per_4k - 1)" -t 2:8309 -c 2:cryptroot $disk
        ^partprobe $disk
        ^udevadm settle
        let parts = ^lsblk -J -lnpo NAME,TYPE $disk | from json | get blockdevices | where type == part | get name
        if ($parts | length) != 2 { die $"expected 2 partitions on ($disk) after partitioning, got ($parts | length)" }
        $luks_pw | ^cryptsetup --batch-mode luksFormat ...$LUKS_FORMAT --key-file - $parts.1
        $luks_pw | ^cryptsetup open ...$LUKS_OPEN --key-file - $parts.1 $LUKS_NAME
        ^mkfs.fat -F 32 -n ESP $parts.0
        ^mkfs.btrfs -f -L arch $"/dev/mapper/($LUKS_NAME)"
        ^mount $"/dev/mapper/($LUKS_NAME)" $MOUNT
        for s in $SUBVOLS { ^btrfs subvolume create ($MOUNT | path join $s.name) }
        ^umount $MOUNT
        for s in $SUBVOLS {
            let at = $"($MOUNT)($s.mount)" | str trim --right --char "/"
            mkdir $at
            ^mount -o $"($BTRFS_OPTS),subvol=($s.name)" $"/dev/mapper/($LUKS_NAME)" $at
        }
        mkdir $"($MOUNT)/boot"
        ^mount -o umask=0077 $parts.0 $"($MOUNT)/boot"
        {esp: $parts.0, root: $parts.1, uuid: (^cryptsetup luksUUID $parts.1 | str trim)}
    }

    span pacstrap {} {
        # pacstrap verifies signatures: needs a synced clock and the iso's keyring refresh to have finished
        for _ in 1..$SYNC_WAIT_S {
            let synced = (^timedatectl show -p NTPSynchronized --value | str trim) == "yes"
            if $synced and (^systemctl is-active --quiet archlinux-keyring-wkd-sync.service | complete).exit_code != 0 { break }
            sleep 1sec
        }
        let ucode = if (open --raw /proc/cpuinfo | str contains GenuineIntel) { "intel-ucode" } else { "amd-ucode" }
        # homelab mirror first so pacstrap and install pull at lan speed, only when it answers; pacstrap copies the list
        let base = $HOMELAB_MIRROR | split row '$' | first
        if $c.homelab and not (open --raw $MIRRORLIST | str contains $base) and (^curl -fs -m $PING_TIMEOUT_S -r 0-0 -o /dev/null $HOMELAB_MIRROR_PROBE | complete).exit_code == 0 {
            $"Server = ($HOMELAB_MIRROR)\n(open --raw $MIRRORLIST)" | save --force $MIRRORLIST
        }
        ^pacstrap -K $MOUNT ...$PACSTRAP $ucode
        if ($MIRROR_COUNTRIES | path exists) { ^install -Dm644 $MIRROR_COUNTRIES $"($MOUNT)($MIRROR_COUNTRIES)" }
        ^genfstab -U $MOUNT | save --append $"($MOUNT)/etc/fstab"
        # stage's temporary unlock: a random key in its own slot, found by systemd-cryptsetup in the initramfs. residual
        # risk: for the chain's hours it sits in plaintext initramfs images on the unencrypted ESP; stage trims the ESP
        # and logs the reencrypt that rotates the volume key
        let key = $"($MOUNT)($STAGE_KEY_FILE)"
        mkdir ($key | path dirname)
        ^chmod 700 ($key | path dirname)
        ^head -c $STAGE_KEY_BYTES /dev/urandom | save --force --raw $key
        ^chmod 600 $key
        # a random key needs no slow kdf, argon2id would only delay every chained boot
        $luks_pw | ^cryptsetup luksAddKey --key-file - --pbkdf pbkdf2 --pbkdf-force-iterations 1000 $parts.root $key
        $"FILES+=\(($STAGE_KEY_FILE)\)\n" | save --force $"($MOUNT)/etc/mkinitcpio.conf.d/dotfiles-stage.conf"
        target-system $c $parts.uuid
    }

    wifi-carry $c
    # the new machine's home, machine-local: no secret ever removes it
    if $c.home_gateway != null { $"($c.home_gateway)\n" | save --force $"($MOUNT)($HOME_GATEWAYS)" }

    # a profile with secrets: pull and unlock them here (the one tap window), so the chained config boot needs no touch
    if "secrets" in $capabilities {
        if (^pacman -Sy --noconfirm --needed ...$SECRETS_TOOLS | complete).exit_code != 0 { log-warn "secrets toolchain install failed, config will unlock instead" }
        ^systemctl start pcscd.socket | complete | ignore
        # not captured: the person reads the touch prompts
        let unlocked = try { with-env {DOTFILES: $repo, PROFILE_FILE: $c.profile_file} { ^nu --no-config-file ($repo | path join scripts dot.nu) secrets unlock }; true } catch { false }
        if not $unlocked { log-warn "secrets unlock skipped" }
    }
    user-setup $c
    stage-arm $c $parts.uuid
    ^umount -R $MOUNT
    ^cryptsetup close $LUKS_NAME
    log-info $"done, rebooting in ($REBOOT_DELAY); remove the ISO. the next boots install and configure by themselves"
    sleep $REBOOT_DELAY
    ^reboot
}
