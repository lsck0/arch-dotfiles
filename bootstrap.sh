#!/usr/bin/env bash
# stage 1, from the Arch ISO via the README line: wipe the disk, install a base system, arm stage.sh
# trust: fetched over https, then master is cloned and nothing runs from it unless HEAD is signed by
# SIGNING_KEY_FINGERPRINT (sync.sh signs every Generation); packages via the ISO archlinux-keyring
# BOOTSTRAP_INSECURE=1 skips the signature check, e.g. before master's HEAD is signed
# wsl (FORM_FACTOR=wsl): run the README line in the fresh distro's root shell, no disk/bootloader/stage;
# keyring, upgrade, user with wheel sudo, wsl.conf, verified repo; then terminate, reopen, install.sh + config.sh
# machine and user are asked apart: the machine is a platforms/<name>.sh (first argument) or a new one, whose answers go to
# /etc/dotfiles/platform.sh; the user is any name, with the profile template profiles/<name>.sh when there is one
# a person at the console gets dialog screens; without a tty or with BOOTSTRAP_ASSUME_YES=1 the plain prompts and env:
# BOOTSTRAP_{USERNAME,DISK,PASSWORD,USER_PASSWORD,ROOT_PASSWORD}, for a new machine also
# BOOTSTRAP_{HOSTNAME,GROUPS,KEYMAP,TIMEZONE,LOCALE} and BOOTSTRAP_HOME_NETWORK=0|1 (unasked and 0 under ASSUME_YES)

set -euo pipefail

# german keyboard before any prompt; the Arch ISO defaults to us layout
loadkeys de-latin1 2>/dev/null || true

DOTFILES_URL=https://github.com/lsck0/arch-dotfiles.git
CLONE_DIR=/tmp/arch-dotfiles
# Luca Sandrock <luca.sandrock@proton.me>: `gpg --show-keys configs/base/gnupg/luca-sandrock.pub.asc`, also https://github.com/lsck0.gpg
SIGNING_KEY_FINGERPRINT=E7501F533316E9AFC6AAE907122F2CB527D1EFE3
SIGNING_KEY_FILE=configs/base/gnupg/luca-sandrock.pub.asc

die() {
    # a leftover dialog screen would hide the reason
    if ((${TUI:-0})); then clear >/dev/tty; fi
    echo "bootstrap: $*" >&2
    exit 1
}

# clone_verify <dir>: dies unless the clone's HEAD has a good signature by SIGNING_KEY_FINGERPRINT
clone_verify() {
    local dir="$1" gnupg_home status signer verdict verified=0
    gnupg_home=$(mktemp -d)
    # the key file comes from the unverified clone, harmless: only the pinned fingerprint passes below
    GNUPGHOME="$gnupg_home" gpg --batch --quiet --import "$dir/$SIGNING_KEY_FILE" || die "cannot import $SIGNING_KEY_FILE"
    status=$(GNUPGHOME="$gnupg_home" git -C "$dir" verify-commit --raw HEAD 2>&1) && verified=1
    GNUPGHOME="$gnupg_home" gpgconf --kill all
    rm -rf "$gnupg_home"
    # gpg status line: VALIDSIG <signing key> ... <primary key>, field 12 counting the [GNUPG:] prefix
    signer=$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" {print $12}' <<<"$status")
    verdict=$(awk '$1 == "[GNUPG:]" && $2 ~ /^(GOOD|BAD|EXP|EXPKEY|REVKEY|ERR)SIG$/ {print $2}' <<<"$status" | paste -sd' ')
    if (( ! verified )) || [[ "$signer" != "$SIGNING_KEY_FINGERPRINT" ]]; then
        die "$DOTFILES_URL HEAD $(git -C "$dir" rev-parse HEAD) is not signed by $SIGNING_KEY_FINGERPRINT" \
            "(gpg: ${verdict:-NOSIG}, primary key: ${signer:-none}), refusing to run it; BOOTSTRAP_INSECURE=1 runs it unverified"
    fi
}

# pacman_init: keyring, full upgrade and what the rest needs; a fresh wsl distro ships an empty keyring and old packages
pacman_init() {
    pacman-key --init
    pacman-key --populate archlinux
    pacman -Syu --noconfirm --needed git gnupg sudo zsh
}

# fetched alone (README line or curl | bash) there is no checkout yet
if [[ -z "${BASH_SOURCE[0]:-}" || ! -f "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/install.sh" ]]; then
    [[ "${BOOTSTRAP_INSECURE:-0}" =~ ^[01]$ ]] || die "BOOTSTRAP_INSECURE is '$BOOTSTRAP_INSECURE', expected 0 or 1"
    # the ISO's pacman-init.service already filled the keyring
    if [[ -d /run/archiso ]]; then pacman -Sy --noconfirm --needed git gnupg; else pacman_init; fi
    rm -rf "$CLONE_DIR"
    git clone "$DOTFILES_URL" "$CLONE_DIR"
    if [[ "${BOOTSTRAP_INSECURE:-0}" == 1 ]]; then
        echo "bootstrap: WARNING: BOOTSTRAP_INSECURE=1, running $(git -C "$CLONE_DIR" rev-parse HEAD) as root WITHOUT checking its signature" >&2
    else
        clone_verify "$CLONE_DIR"
    fi
    # the prompts read the console; piped over ssh without -t there is none, and BOOTSTRAP_ASSUME_YES needs none
    if { : </dev/tty; } 2>/dev/null; then exec bash "$CLONE_DIR/bootstrap.sh" "$@" </dev/tty; fi
    exec bash "$CLONE_DIR/bootstrap.sh" "$@" </dev/null
fi

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PLATFORM="${1:-}"
# SYSTEM_REPO, SYSTEM_STATE, system_copy; PLATFORM_LOCAL, platform_groups_all
source "$REPO/scripts/lib/system.sh"
source "$REPO/scripts/lib/platform.sh"

# defaults, overridden per platform
KEYMAP=de-latin1
TIMEZONE=Europe/Berlin
LOCALE=en_US.UTF-8
ESP_SIZE_MIB=1024
HOSTNAME=""

LUKS_NAME=root
MOUNT=/mnt
# the installed system's root: the mounted disk from the ISO, the running distro under wsl
TARGET_ROOT=$MOUNT
BTRFS_OPTS="noatime,compress=zstd"
SUBVOLS=("@:/" "@home:/home" "@log:/var/log" "@pkg:/var/cache/pacman/pkg")
# the README's former manual reencrypt, done at format time instead
LUKS_FORMAT=(--type luks2 --cipher aes-xts-plain64 --key-size 512 --sector-size 4096 --pbkdf argon2id)
LUKS_OPEN=(--allow-discards --perf-no_read_workqueue --perf-no_write_workqueue --persistent)
STAGE_STATE_DIR=/var/lib/dotfiles-stage
STAGE_KEY_FILE=/etc/cryptsetup-keys.d/root.key
EFI_GLOBAL_GUID=8be4df61-93ca-11d2-aa0d-00e098032b8c
REBOOT_DELAY_S=10
SYNC_WAIT_S=120
NETWORK_TIMEOUT_S=10

# the platform menu's entry for a machine without a platform file
PLATFORM_NEW=new
LOGIN_SHELL=/usr/bin/zsh
SUDOERS_WHEEL="$REPO/configs/base/sudo/10-wheel"
# the networkmanager module's home rule: a link is home while its default gateway's mac is listed here
HOME_GATEWAYS=/etc/NetworkManager/home-gateways
MAC_PATTERN='^([0-9a-f]{2}:){5}[0-9a-f]{2}$'
PING_TIMEOUT_S=2
USERNAME_PATTERN='^[a-z_][a-z0-9_-]{0,31}$'
HOSTNAME_PATTERN='^[A-Za-z0-9][A-Za-z0-9-]{0,62}$'
KEYMAP_PATTERN='^[A-Za-z0-9_-]+$'
TIMEZONE_PATTERN='^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+){0,2}$'
TUI=0
TUI_WIDTH=72
# rows around the text: frame and buttons, an inputbox's field on top; dialog's own auto height drops wrapped text
TUI_BOX_ROWS=4
TUI_INPUT_ROWS=7
TUI_TEXT_MARGIN=6
TUI_BACKTITLE="arch-dotfiles bootstrap"
# console keymaps systemd's kbd-model-map turns into an x11 layout, so the desktop follows too
COMMON_KEYMAPS=(
    de-latin1 "German" us "English (US)" uk "English (UK)" fr-latin1 "French" es "Spanish" it "Italian"
    pl2 "Polish" sv-latin1 "Swedish" dk "Danish" no "Norwegian" "fi" "Finnish" pt-latin1 "Portuguese"
    br-abnt2 "Brazilian" be-latin1 "Belgian" sg-latin1 "Swiss German" dvorak "US Dvorak"
)
# a guest's group menu; base is the one every other group builds on
REQUIRED_GROUP=base
declare -A GROUP_DESCRIPTIONS=(
    [base]="shell, cli tools, pacman, security and system services"
    [creating]="image, audio, video and 3d editors, obs"
    [desktop]="hyprland and plasma, browsers, terminals, apps"
    [fonts]="noto, nerd and cjk fonts"
    [gaming]="steam, lutris, heroic, proton and game tooling"
    [hardware]="firmware, drivers, audio, power, firewall, boot"
    [latex]="tex engine, pdf viewer, zotero"
    [llm]="local language models with ollama"
    [pentesting]="security auditing and pentest tools"
    [programming]="compilers, editors, language servers, docker"
    [qemu]="virtual machines, waydroid, distrobox"
    [rocm]="amd gpu compute (ollama, pytorch), amd only"
    [socials]="discord, signal, telegram, spotify, thunderbird"
)

# tui_init: dialog for a person at the console, installed into the live system on demand; plain prompts otherwise
tui_init() {
    [[ "${BOOTSTRAP_ASSUME_YES:-0}" != 1 && "${TERM:-dumb}" != dumb ]] || return 0
    { : </dev/tty >/dev/tty; } 2>/dev/null || return 0
    if ! command -v dialog >/dev/null; then
        if ! curl -fsI -m "$NETWORK_TIMEOUT_S" https://archlinux.org >/dev/null 2>&1 \
            || ! pacman -Sy --noconfirm --needed dialog >/dev/null 2>&1; then
            echo "bootstrap: dialog unavailable, using plain prompts" >&2
            return 0
        fi
    fi
    TUI=1
}

# tui_end: the screens are done, so later output and errors stay readable
tui_end() {
    if ((TUI)); then clear >/dev/tty; fi
    TUI=0
}

# dlg <dialog args...>: the answer on stdout, the screens on the tty; cancel or esc quits bootstrap
# callers add || exit 1: bash drops set -e inside $(...), so a cancel would not reach the main shell
dlg() {
    dialog --backtitle "$TUI_BACKTITLE" --cr-wrap --output-fd 3 "$@" 3>&1 1>/dev/tty </dev/tty || die "aborted"
}

# tui_height <text> <frame rows>: rows for a box showing <text> wrapped to TUI_WIDTH
tui_height() {
    echo $(($(fold -s -w "$((TUI_WIDTH - TUI_TEXT_MARGIN))" <<<"$1" | wc -l) + $2))
}

# ask <check> <label> <text> <default>: an answer <check> accepts; the default as is under BOOTSTRAP_ASSUME_YES=1
ask() {
    local check="$1" label="$2" text="$3" default="$4" answer note=""
    if [[ "${BOOTSTRAP_ASSUME_YES:-0}" == 1 ]]; then printf '%s' "$default"; return; fi
    while :; do
        if ((TUI)); then
            answer=$(dlg --title "$label" --inputbox "$note$text" "$(tui_height "$note$text" "$TUI_INPUT_ROWS")" "$TUI_WIDTH" "$default") || exit 1
        else
            read -rp "$label [$default]: " answer </dev/tty || exit 1
            answer="${answer:-$default}"
        fi
        "$check" "$answer" && break
        note="'$answer' is not valid, try again."
        ((TUI)) || echo "bootstrap: $note" >&2
        note+=$'\n\n'
    done
    printf '%s' "$answer"
}

# disk_label <disk>: its size and model on one line
disk_label() { lsblk -dno SIZE,MODEL "$1" | tr -s ' ' | sed 's/^ //; s/ $//'; }

username_valid() { [[ "$1" =~ $USERNAME_PATTERN ]]; }
hostname_valid() { [[ "$1" =~ $HOSTNAME_PATTERN ]]; }
# a new machine's name is none of the platforms/ files, those are other machines
hostname_new_valid() { hostname_valid "$1" && [[ ! -e "$REPO/platforms/$1.sh" ]]; }
timezone_valid() { [[ "$1" =~ $TIMEZONE_PATTERN && -f "/usr/share/zoneinfo/$1" ]]; }
# the iso's locale.gen lists every locale the installed glibc can generate
locale_valid() { awk -v locale="$1" '{ sub(/^#/, "") } $1 == locale { found = 1 } END { exit !found }' /etc/locale.gen; }
# loading is the check, and the layout is live before any later answer or password is typed
keymap_load() { [[ "$1" =~ $KEYMAP_PATTERN ]] && loadkeys "$1" >/dev/null 2>&1; }

# ask_keymap: a guest's console keymap, from the common ones or any other by name
ask_keymap() {
    local keymap
    if ((!TUI)); then
        ask keymap_load keymap "" "$KEYMAP"
        return
    fi
    keymap=$(dlg --title keyboard --default-item "$KEYMAP" --menu "Keyboard layout (console, boot password prompt, desktop). Applies now." 0 "$TUI_WIDTH" 0 \
        "${COMMON_KEYMAPS[@]}" other "type another console keymap") || exit 1
    if [[ "$keymap" == other ]]; then
        keymap=$(ask keymap_load keymap "Console keymap name, as in /usr/share/kbd/keymaps, e.g. cz, hu, ru, trq:" "") || exit 1
    fi
    printf '%s' "$keymap"
}

confirm() {
    [[ "${BOOTSTRAP_ASSUME_YES:-0}" == 1 ]] && return 0
    local answer
    read -rp "$1 " answer </dev/tty
    [[ "$answer" == "$2" ]]
}

# read_password <prompt>: hidden, typed twice unless empty, so the caller can apply its default
read_password() {
    local first second
    read -rsp "$1: " first </dev/tty; echo >&2
    if [[ -n "$first" ]]; then
        read -rsp "again: " second </dev/tty; echo >&2
        [[ "$first" == "$second" ]] || die "passwords differ"
    fi
    printf '%s' "$first"
}

# ask_password <label> <hint> <empty_ok>: read_password, or a dialog that asks again on a mismatch or a refused empty one
ask_password() {
    local label="$1" hint="$2" empty_ok="$3" first second note=""
    if ((!TUI)); then
        echo "$hint" >&2
        read_password "$label"
        return
    fi
    while :; do
        first=$(dlg --title "$label" --insecure --passwordbox "$note$hint" "$(tui_height "$note$hint" "$TUI_INPUT_ROWS")" "$TUI_WIDTH") || exit 1
        if [[ -z "$first" ]]; then
            ((empty_ok)) && break
            note="It must not be empty."$'\n\n'
            continue
        fi
        second=$(dlg --title "$label" --insecure --passwordbox "The same again:" "$(tui_height "The same again:" "$TUI_INPUT_ROWS")" "$TUI_WIDTH") || exit 1
        [[ "$first" == "$second" ]] && break
        note="The two did not match, once more."$'\n\n'
    done
    printf '%s' "$first"
}

# in_target <cmd...>: run in the installed system, through arch-chroot from the ISO, directly under wsl
in_target() {
    if [[ -n "$TARGET_ROOT" ]]; then arch-chroot "$TARGET_ROOT" "$@"; else "$@"; fi
}

# patches_mark <record> <system|user>: every patch of that scope as applied, the fresh machine or user needs none; a rerun keeps the record
patches_mark() {
    local record="$1" scope="$2" patch patch_scope
    [[ ! -e "$record" ]] || return 0
    mkdir -p "${record%/*}"
    for patch in "$REPO"/patches/[0-9][0-9]_*.sh; do
        patch_scope=system
        [[ "$patch" != *.user.sh ]] || patch_scope=user
        if [[ -f "$patch" && "$patch_scope" == "$scope" ]]; then basename "$patch"; fi
    done >"$record"
}

# user_setup: the login user with its password, wheel and zsh, root locked unless given one, the verified repo at home and
# as the root copy, the machine's and the user's facts, both patch records
user_setup() {
    local home="$TARGET_ROOT/home/$USERNAME"
    local repo_copy="$home/projects/arch-dotfiles" profile="$home/.config/dotfiles/profile.sh"
    in_target id -u "$USERNAME" >/dev/null 2>&1 || in_target useradd -m -G wheel -s "$LOGIN_SHELL" "$USERNAME"
    printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | in_target chpasswd
    in_target passwd -l root >/dev/null
    # root keeps that lock unless it was given its own password
    [[ -z "$ROOT_PASSWORD" ]] || printf 'root:%s\n' "$ROOT_PASSWORD" | in_target chpasswd
    # sudo skips a drop-in named with a dot, so this one is checked before it can lock anyone out
    install -Dm440 "$SUDOERS_WHEEL" "$TARGET_ROOT/etc/sudoers.d/10-wheel.new"
    in_target visudo -cqf /etc/sudoers.d/10-wheel.new || die "the wheel sudoers drop-in does not parse"
    mv -f "$TARGET_ROOT/etc/sudoers.d/10-wheel.new" "$TARGET_ROOT/etc/sudoers.d/10-wheel"
    # a rerun under wsl keeps the checkout and whatever work is in it
    if [[ ! -e "$repo_copy" ]]; then
        mkdir -p "${repo_copy%/*}"
        cp -a "$REPO" "$repo_copy"
    fi
    # a new machine's answers become its platform file, root-owned; FORM_FACTOR stays a probe
    if [[ "$PLATFORM" == "$PLATFORM_NEW" ]]; then
        printf 'HOSTNAME=%q\nPKG_GROUPS=(%s)\n' "$HOSTNAME" "$(printf '%q ' "${PKG_GROUPS[@]}")" \
            | install -Dm644 /dev/stdin "$TARGET_ROOT$PLATFORM_LOCAL"
    else
        # platform_file prefers it, so a rerun's earlier answers must not outlive the platforms/ file chosen now
        rm -f "$TARGET_ROOT$PLATFORM_LOCAL"
    fi
    # the user's facts: the template of the same name, nothing for a guest
    if [[ -f "$PROFILE_FILE" && ! -e "$profile" ]]; then install -Dm644 "$PROFILE_FILE" "$profile"; fi
    # the system layer only ever runs from this root-owned copy of the verified clone
    system_copy "$REPO" "$TARGET_ROOT$SYSTEM_REPO" || die "cannot seed the root copy $TARGET_ROOT$SYSTEM_REPO"
    patches_mark "$TARGET_ROOT$SYSTEM_STATE/patches-applied" system
    patches_mark "$home/.local/state/dotfiles/patches-applied" user
    in_target chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"
}

# keyfile_escape <value>: a GKeyFile string, as NetworkManager's keyfiles read it: backslash, control characters and a
# leading space escaped
keyfile_escape() {
    local value="${1//\\/\\\\}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\t'/\\t}"
    value="${value//$'\r'/\\r}"
    [[ "$value" != " "* ]] || value="\\s${value:1}"
    printf '%s' "$value"
}

# home_gateway_mac: the mac of the router this live system routes through, lowercase; fails without one
home_gateway_mac() {
    local route gw dev mac
    route=$(ip -4 route show default | head -n1)
    gw=$(awk '{ for (i = 1; i < NF; i++) if ($i == "via") print $(i + 1) }' <<<"$route")
    dev=$(awk '{ for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1) }' <<<"$route")
    [[ -n "$gw" && -n "$dev" ]] || return 1
    # the neighbour cache may not hold the router yet
    ping -c 1 -W "$PING_TIMEOUT_S" -I "$dev" "$gw" >/dev/null 2>&1 || true
    mac=$(ip neigh show "$gw" dev "$dev" | awk '{ for (i = 1; i < NF; i++) if ($i == "lladdr") print tolower($(i + 1)) }')
    [[ "$mac" =~ $MAC_PATTERN ]] || return 1
    echo "$mac"
}

# home_ssid: the wifi this live system is on, nothing when wired
home_ssid() {
    local dev
    dev=$(ip -4 route show default | awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
    [[ -n "$dev" ]] && command -v iw >/dev/null || return 0
    iw dev "$dev" link 2>/dev/null | sed -n 's/^[[:space:]]*SSID: //p'
}

# ask_home_network: 1 when the person says the current network is their home, else 0; never asked unattended
ask_home_network() {
    local text status=0 answer
    [[ "${BOOTSTRAP_ASSUME_YES:-0}" != 1 ]] || { printf 0; return; }
    text="Is the network you are on now your home network?

Yes remembers its router as home: there this machine finds printers and other devices on its own (mDNS) and keeps its real network address. Every other network stays locked down.

No locks down every network, this one included."
    if ((TUI)); then
        dialog --backtitle "$TUI_BACKTITLE" --cr-wrap --title "home network" --defaultno --yesno "$text" \
            "$(tui_height "$text" "$TUI_BOX_ROWS")" "$TUI_WIDTH" </dev/tty >/dev/tty || status=$?
        # yes 0, no 1, esc quits like every other screen
        ((status <= 1)) || die "aborted"
        printf '%s' $((status == 0))
    else
        read -rp "is the network you are on now your home network? [y/N] " answer </dev/tty || exit 1
        if [[ "$answer" == y ]]; then printf 1; else printf 0; fi
    fi
}

# --- preflight ----------------------------------------------------------------

[[ $EUID -eq 0 ]] || die "run as root"
IN_WSL=0; [[ "$(systemd-detect-virt 2>/dev/null)" == wsl ]] && IN_WSL=1
tui_init

if ((IN_WSL)); then
    welcome="WSL setup: a user with sudo, the checkout, wsl.conf. Then restart the distro and run install.sh + config.sh.

Esc or Cancel quits."
else
    welcome="Installs Arch Linux with the arch-dotfiles. Questions first (nothing written until you confirm), then the chosen disk is ERASED and encrypted, then unattended reboots while it installs (can take hours; stay plugged in and online).

Esc or Cancel quits."
fi
if ((TUI)); then dlg --title welcome --msgbox "$welcome" "$(tui_height "$welcome" "$TUI_BOX_ROWS")" "$TUI_WIDTH"; fi

# the user: any name; a profile template of the same name brings its owner's secrets, identity and homelab, else a guest
mapfile -t profiles < <(cd "$REPO/profiles" && for f in *.sh; do [[ -f "$f" ]] && echo "${f%.sh}"; done)
username_text="Your login name. A name with a profile (${profiles[*]:-none}) gets that profile's secrets/identity/homelab; any other name is a guest (same desktop and tools, no personal parts)."
# wsl types on the windows layout, the console is german until a new machine's layout screen
((IN_WSL)) || username_text+=$'\n\nThe keyboard is German until the layout screen: y and z are swapped.'
USERNAME="${BOOTSTRAP_USERNAME:-$(ask username_valid username "$username_text" "${profiles[0]:-}")}"
username_valid "$USERNAME" || die "invalid username '$USERNAME', expected $USERNAME_PATTERN"
# the template stands in for the profile until user_setup copies it home; yubikey.sh honours it too
export PROFILE_FILE="$REPO/profiles/$USERNAME.sh"
source "$REPO/scripts/lib/profile.sh"
profile_load

# the machine: a platform file sets HOSTNAME, PKG_GROUPS and the machine facts; a new one is asked for its own
mapfile -t platforms < <(cd "$REPO/platforms" && for f in *.sh; do [[ -f "$f" ]] && echo "${f%.sh}"; done)
if [[ -z "$PLATFORM" ]] && [[ "${BOOTSTRAP_ASSUME_YES:-0}" == 1 ]]; then
    PLATFORM=$PLATFORM_NEW
elif [[ -z "$PLATFORM" ]] && ((TUI)); then
    platform_items=()
    for p in "${platforms[@]}"; do platform_items+=("$p" "$(sed -n 's/^FORM_FACTOR=//p' "$REPO/platforms/$p.sh")"); done
    platform_items+=("$PLATFORM_NEW" "any other machine: a few questions")
    PLATFORM=$(dlg --title machine --default-item "$PLATFORM_NEW" --menu "Which machine is this?" 0 "$TUI_WIDTH" 0 "${platform_items[@]}")
elif [[ -z "$PLATFORM" ]]; then
    echo "platforms: ${platforms[*]} $PLATFORM_NEW"
    read -rp "platform [$PLATFORM_NEW]: " PLATFORM </dev/tty
    PLATFORM="${PLATFORM:-$PLATFORM_NEW}"
fi

HOME_NETWORK=0
HOME_GATEWAY=""
HOME_SSID=""
if [[ "$PLATFORM" != "$PLATFORM_NEW" ]]; then
    PLATFORM_FILE="$REPO/platforms/$PLATFORM.sh"
    [[ -f "$PLATFORM_FILE" ]] || die "unknown platform '$PLATFORM', one of: ${platforms[*]} $PLATFORM_NEW"
    # shellcheck source=/dev/null
    source "$PLATFORM_FILE"
    [[ -n "$HOSTNAME" ]] || die "$PLATFORM_FILE sets no HOSTNAME"
else
    # no platform file, so everything comes from env/prompt (env for an unattended run)
    # nor one to say wsl, so the distro itself does
    (( ! IN_WSL )) || FORM_FACTOR=wsl
    # wsl has no console, initramfs or locale of its own to set
    if (( ! IN_WSL )); then
        KEYMAP="${BOOTSTRAP_KEYMAP:-$(ask_keymap)}"
        keymap_load "$KEYMAP" || die "unknown keymap '$KEYMAP'"
    fi
    HOSTNAME="${BOOTSTRAP_HOSTNAME:-$(ask hostname_new_valid hostname "The machine's name on the network: letters, digits and dashes, none of ${platforms[*]}." "$USERNAME-pc")}"
    hostname_new_valid "$HOSTNAME" || die "invalid hostname '$HOSTNAME', expected $HOSTNAME_PATTERN and none of: ${platforms[*]}"
    if (( ! IN_WSL )); then
        TIMEZONE="${BOOTSTRAP_TIMEZONE:-$(ask timezone_valid timezone "Region/City, e.g. Europe/London. Later follows your location on its own." "$TIMEZONE")}"
        timezone_valid "$TIMEZONE" || die "unknown timezone '$TIMEZONE'"
        LOCALE="${BOOTSTRAP_LOCALE:-$(ask locale_valid locale "Language and formats, e.g. en_US.UTF-8, de_DE.UTF-8." "$LOCALE")}"
        locale_valid "$LOCALE" || die "unknown locale '$LOCALE'"
        # asked once, while still on that network: its router's mac is what the installed machine recognises home by
        HOME_NETWORK="${BOOTSTRAP_HOME_NETWORK:-$(ask_home_network)}" || exit 1
        [[ "$HOME_NETWORK" =~ ^[01]$ ]] || die "BOOTSTRAP_HOME_NETWORK is '$HOME_NETWORK', expected 0 or 1"
        if ((HOME_NETWORK)); then
            HOME_GATEWAY=$(home_gateway_mac) || echo "bootstrap: no router mac found, every network stays foreign" >&2
            HOME_SSID=$(home_ssid)
        fi
    fi
    # every group install.sh tags; a new machine picks from these, platform files pick for the known ones
    mapfile -t GROUP_UNIVERSE < <(platform_groups_all "$REPO")
    if [[ -n "${BOOTSTRAP_GROUPS:-}" ]]; then
        read -ra PKG_GROUPS <<<"$BOOTSTRAP_GROUPS"
    elif [[ "${BOOTSTRAP_ASSUME_YES:-0}" == 1 ]]; then
        PKG_GROUPS=("${GROUP_UNIVERSE[@]}")
    elif ((TUI)); then
        group_items=()
        for grp in "${GROUP_UNIVERSE[@]}"; do
            [[ "$grp" == "$REQUIRED_GROUP" ]] || group_items+=("$grp" "${GROUP_DESCRIPTIONS[$grp]:-}" on)
        done
        groups_chosen=$(dlg --title "package groups" --separate-output --checklist "Space toggles, Enter accepts. '$REQUIRED_GROUP' (${GROUP_DESCRIPTIONS[$REQUIRED_GROUP]}) is always installed." 0 "$TUI_WIDTH" 0 "${group_items[@]}")
        mapfile -t PKG_GROUPS < <(printf '%s' "$groups_chosen")
        PKG_GROUPS=("$REQUIRED_GROUP" "${PKG_GROUPS[@]}")
    else
        echo "package groups ($REQUIRED_GROUP always):" >&2
        for i in "${!GROUP_UNIVERSE[@]}"; do printf '  %d  %s\n' "$((i + 1))" "${GROUP_UNIVERSE[i]}" >&2; done
        read -rp "numbers to EXCLUDE (space-separated), enter for all: " -a excludes </dev/tty
        PKG_GROUPS=()
        for i in "${!GROUP_UNIVERSE[@]}"; do
            skip=0
            for n in "${excludes[@]}"; do [[ "$n" == "$((i + 1))" ]] && skip=1; done
            (( skip )) || PKG_GROUPS+=("${GROUP_UNIVERSE[i]}")
        done
    fi
    # before anything is erased: only discovered groups (they end up in a file root sources), base always
    [[ " ${PKG_GROUPS[*]} " == *" $REQUIRED_GROUP "* ]] || PKG_GROUPS=("$REQUIRED_GROUP" "${PKG_GROUPS[@]}")
    for grp in "${PKG_GROUPS[@]}"; do
        [[ " ${GROUP_UNIVERSE[*]} " == *" $grp "* ]] || die "unknown package group '$grp', one of: ${GROUP_UNIVERSE[*]}"
    done
fi

# --- wsl ----------------------------------------------------------------------

# the distro's own root shell instead of the ISO: windows owns disk, kernel and boot
if [[ "${FORM_FACTOR:-}" == wsl ]]; then
    [[ "$(systemd-detect-virt 2>/dev/null)" == wsl ]] || die "$PLATFORM is a wsl platform, run it in the distro's root shell"
    USER_PASSWORD="${BOOTSTRAP_USER_PASSWORD:-}"
    [[ -n "$USER_PASSWORD" ]] || USER_PASSWORD=$(ask_password "$USERNAME password" "For login and sudo." 0)
    [[ -n "$USER_PASSWORD" ]] || die "empty password"
    ROOT_PASSWORD="${BOOTSTRAP_ROOT_PASSWORD:-}"
    tui_end
    pacman_init
    TARGET_ROOT=""
    user_setup
    echo "$HOSTNAME" >/etc/hostname
    sed -e "s|@USER@|$USERNAME|" -e "s|@HOSTNAME@|$HOSTNAME|" "$REPO/configs/base/wsl/wsl.conf" | install -Dm644 /dev/stdin /etc/wsl.conf
    echo "bootstrap: done. from windows: wsl --terminate archlinux, reopen it (now $USERNAME with systemd), then:"
    echo "  cd ~/projects/arch-dotfiles && ./install.sh && ./config.sh"
    exit 0
fi

[[ -d /run/archiso ]] || die "not running from the Arch ISO"
[[ -d /sys/firmware/efi ]] || die "not booted in UEFI mode"
curl -fsI -m "$NETWORK_TIMEOUT_S" https://archlinux.org >/dev/null || die "no network"

setup_mode="$(od -An -t u1 "/sys/firmware/efi/efivars/SetupMode-$EFI_GLOBAL_GUID" 2>/dev/null | awk '{print $NF}')"
if [[ "$setup_mode" != 1 ]] && ((TUI)); then
    secure_boot_text="Firmware not in Secure Boot Setup Mode, so install.sh cannot enroll keys. Continue without Secure Boot? (To use it: quit, clear the keys / enable Setup Mode in firmware, rerun.)"
    dlg --title "secure boot" --defaultno --yesno "$secure_boot_text" "$(tui_height "$secure_boot_text" "$TUI_BOX_ROWS")" "$TUI_WIDTH"
elif [[ "$setup_mode" != 1 ]]; then
    echo "bootstrap: firmware is not in Secure Boot Setup Mode, so install.sh cannot enroll keys" >&2
    confirm "continue without Secure Boot? [y/N]" y || die "enable Setup Mode in the firmware, then rerun"
fi

# --- disk ---------------------------------------------------------------------

DISK="${BOOTSTRAP_DISK:-}"
if [[ -z "$DISK" ]]; then
    mapfile -t disks < <(lsblk -dnpo NAME,TYPE,RM | awk '$2 == "disk" && $3 == 0 {print $1}' | grep -v -e zram -e loop)
    (( ${#disks[@]} )) || die "no disk found (set BOOTSTRAP_DISK)"
    if (( ${#disks[@]} == 1 )); then
        DISK="${disks[0]}"
    elif ((TUI)); then
        disk_items=()
        for d in "${disks[@]}"; do disk_items+=("$d" "$(disk_label "$d")"); done
        DISK=$(dlg --title disk --menu "Which disk gets erased and installed to?" 0 "$TUI_WIDTH" 0 "${disk_items[@]}")
    else
        lsblk -dpo NAME,SIZE,MODEL "${disks[@]}" >&2
        PS3="disk to erase: "
        select d in "${disks[@]}"; do [[ -n "$d" ]] && { DISK="$d"; break; }; done </dev/tty
    fi
fi
[[ -b "$DISK" ]] || die "$DISK is not a block device"

erase_prompt="ERASE ALL DATA on $DISK? type the device path to confirm:"
if ((TUI)); then
    erase_text="$(lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL "$DISK")

$erase_prompt"
    erase_answer=$(dlg --title "erase $DISK" --no-collapse --inputbox "$erase_text" "$(tui_height "$erase_text" "$TUI_INPUT_ROWS")" "$TUI_WIDTH")
    [[ "$erase_answer" == "$DISK" ]] || die "aborted"
else
    lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL "$DISK"
    confirm "$erase_prompt" "$DISK" || die "aborted"
fi

# the passwords must be typed on the layout the LUKS prompt and the console login will use
loadkeys "$KEYMAP"
# unattended: BOOTSTRAP_PASSWORD is the LUKS one and nothing is asked; the user's defaults to it, root stays locked
LUKS_PASSWORD="${BOOTSTRAP_PASSWORD:-}"
USER_PASSWORD="${BOOTSTRAP_USER_PASSWORD:-}"
ROOT_PASSWORD="${BOOTSTRAP_ROOT_PASSWORD:-}"
if [[ -z "$LUKS_PASSWORD" ]]; then
    LUKS_PASSWORD=$(ask_password "LUKS password" "Disk encryption password, asked at every boot on the $KEYMAP layout." 0)
    [[ -n "$LUKS_PASSWORD" ]] || die "empty LUKS password"
    [[ -n "$USER_PASSWORD" ]] || USER_PASSWORD=$(ask_password "$USERNAME password [LUKS password]" "For login and sudo; empty uses the LUKS password." 1)
    [[ -n "$ROOT_PASSWORD" ]] || ROOT_PASSWORD=$(ask_password "root password [locked]" "Empty keeps root locked (sudo still works; no emergency shell)." 1)
fi
USER_PASSWORD="${USER_PASSWORD:-$LUKS_PASSWORD}"

# the last stop before the disk is touched
summary_user="$USERNAME (guest)"; [[ ! -f "$PROFILE_FILE" ]] || summary_user="$USERNAME (profile: ${PROFILE_CAPABILITIES[*]:-none})"
summary_home="no, every network locked down"
((!HOME_NETWORK)) || summary_home="router ${HOME_GATEWAY:-not found}${HOME_SSID:+, wifi $HOME_SSID}"
summary_secure_boot="skipped, not in Setup Mode"; [[ "$setup_mode" != 1 ]] || summary_secure_boot="keys get enrolled"
summary_root=locked; [[ -z "$ROOT_PASSWORD" ]] || summary_root="own password"
summary="user         $summary_user
machine      $PLATFORM
hostname     $HOSTNAME
keyboard     $KEYMAP
timezone     $TIMEZONE
locale       $LOCALE
groups       ${PKG_GROUPS[*]}
home network $summary_home
disk         $DISK $(disk_label "$DISK"), erased
secure boot  $summary_secure_boot
root         $summary_root"
summary_text="$summary

Install now? This erases $DISK."
if ((TUI)); then
    dlg --title summary --no-collapse --yes-label install --no-label quit --yesno "$summary_text" "$(tui_height "$summary_text" "$TUI_BOX_ROWS")" "$TUI_WIDTH"
else
    echo "$summary"
fi
tui_end

# --- partition, encrypt, format -----------------------------------------------

umount -R "$MOUNT" 2>/dev/null || true
cryptsetup close "$LUKS_NAME" 2>/dev/null || true
wipefs -af "$DISK"
sgdisk --zap-all "$DISK"
sgdisk -n "1:0:+${ESP_SIZE_MIB}M" -t 1:ef00 -c 1:ESP "$DISK"
# LUKS with 4096-byte sectors needs the partition size in whole 4 KiB, the free space rarely is
sectors_per_4k=$((4096 / $(blockdev --getss "$DISK")))
root_start=$(sgdisk -F "$DISK")
root_last=$(sgdisk -E "$DISK")
root_end=$((root_start + (root_last - root_start + 1) / sectors_per_4k * sectors_per_4k - 1))
sgdisk -n "2:$root_start:$root_end" -t 2:8309 -c 2:cryptroot "$DISK"
partprobe "$DISK"
udevadm settle
mapfile -t parts < <(lsblk -lnpo NAME,TYPE "$DISK" | awk '$2 == "part" {print $1}')
(( ${#parts[@]} == 2 )) || die "expected 2 partitions on $DISK after partitioning, got ${#parts[@]}"
ESP_PART="${parts[0]}"
ROOT_PART="${parts[1]}"

printf '%s' "$LUKS_PASSWORD" | cryptsetup --batch-mode luksFormat "${LUKS_FORMAT[@]}" --key-file - "$ROOT_PART"
printf '%s' "$LUKS_PASSWORD" | cryptsetup open "${LUKS_OPEN[@]}" --key-file - "$ROOT_PART" "$LUKS_NAME"
LUKS_UUID="$(cryptsetup luksUUID "$ROOT_PART")"
ROOT_DEV="/dev/mapper/$LUKS_NAME"

mkfs.fat -F 32 -n ESP "$ESP_PART"
mkfs.btrfs -f -L arch "$ROOT_DEV"

mount "$ROOT_DEV" "$MOUNT"
for entry in "${SUBVOLS[@]}"; do btrfs subvolume create "$MOUNT/${entry%%:*}"; done
umount "$MOUNT"
for entry in "${SUBVOLS[@]}"; do
    mountpoint="$MOUNT${entry#*:}"
    mkdir -p "$mountpoint"
    mount -o "$BTRFS_OPTS,subvol=${entry%%:*}" "$ROOT_DEV" "$mountpoint"
done
mkdir -p "$MOUNT/boot"
mount -o umask=0077 "$ESP_PART" "$MOUNT/boot"

# --- base system --------------------------------------------------------------

# pacstrap verifies signatures: needs a synced clock and the iso's keyring refresh to have finished
for ((i = 0; i < SYNC_WAIT_S; i++)); do
    [[ "$(timedatectl show -p NTPSynchronized --value)" == yes ]] \
        && ! systemctl is-active --quiet archlinux-keyring-wkd-sync.service && break
    sleep 1
done

ucode=amd-ucode
grep -q GenuineIntel /proc/cpuinfo && ucode=intel-ucode

# homelab mirror first so pacstrap pulls base at lan speed; pacman falls through to the iso's public mirrors when away
[[ "${HOMELAB:-}" != 1 ]] || sed -i '1i Server = http://10.100.0.109:8090/archlinux/$repo/os/$arch' /etc/pacman.d/mirrorlist

pacstrap -K "$MOUNT" base linux linux-firmware mkinitcpio "$ucode" btrfs-progs cryptsetup grub efibootmgr \
    networkmanager sudo git zsh zram-generator libfido2
genfstab -U "$MOUNT" >>"$MOUNT/etc/fstab"

# the ukis (configs/hardware/boot) embed this file as their only cmdline
mkdir -p "$MOUNT/etc/kernel"
echo "rd.luks.name=$LUKS_UUID=$LUKS_NAME root=$ROOT_DEV rootflags=subvol=@ rw zswap.enabled=0 nmi_watchdog=0 slab_nomerge init_on_alloc=1 init_on_free=1 randomize_kstack_offset=on vsyscall=none page_alloc.shuffle=1" >"$MOUNT/etc/kernel/cmdline"

# stage.sh's temporary unlock: a random key in its own slot, found by systemd-cryptsetup in the initramfs as /etc/cryptsetup-keys.d/<volume>.key; stage.sh kills the slot when the chain ends
install -dm700 "$MOUNT/etc/cryptsetup-keys.d"
head -c 64 /dev/urandom >"$MOUNT$STAGE_KEY_FILE"
chmod 600 "$MOUNT$STAGE_KEY_FILE"
# a random key needs no slow kdf, argon2id would only delay every chained boot
printf '%s' "$LUKS_PASSWORD" | cryptsetup luksAddKey --key-file - --pbkdf pbkdf2 --pbkdf-force-iterations 1000 \
    "$ROOT_PART" "$MOUNT$STAGE_KEY_FILE"
install -Dm644 /dev/stdin "$MOUNT/etc/mkinitcpio.conf.d/dotfiles-stage.conf" <<<"FILES+=($STAGE_KEY_FILE)"

arch-chroot "$MOUNT" /bin/bash -euo pipefail -s -- "$HOSTNAME" "$KEYMAP" "$TIMEZONE" "$LOCALE" <<'CHROOT'
hostname=$1 keymap=$2 timezone=$3 locale=$4

ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
hwclock --systohc
sed -i "s/^#\($locale \)/\1/" /etc/locale.gen
locale-gen
echo "LANG=$locale" >/etc/locale.conf
echo "KEYMAP=$keymap" >/etc/vconsole.conf
echo "$hostname" >/etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 %s\n' "$hostname" >/etc/hosts

# systemd initramfs: sd-vconsole so the LUKS prompt uses the right keymap
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

systemctl enable NetworkManager.service NetworkManager-wait-online.service systemd-timesyncd.service

# plain GRUB for the Setup Mode stage boots; configs/hardware/boot/grub reinstalls it to chainload only signed ukis
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$(cat /etc/kernel/cmdline)\"|" /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
# EFI/BOOT/BOOTX64.EFI as well, for firmware that forgets its boot entries
grub-install --target=x86_64-efi --efi-directory=/boot --removable
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT

# zram swap from the first boot, install.sh compiles for hours before config.sh would link it
install -Dm644 "$REPO/configs/hardware/zram/zram-generator.conf" "$MOUNT/etc/systemd/zram-generator.conf"

# --- network --------------------------------------------------------------------

# the wifi the ISO connected with (iwctl), so the chained boots come up online
for psk in /var/lib/iwd/*.psk; do
    [[ -f "$psk" ]] || continue
    # iwd's own name is path-safe: letters, digits, '-', '_' and spaces, else =<hex>
    name=$(basename "$psk" .psk)
    ssid=$name
    if [[ "$ssid" == =* ]]; then
        ssid=$(printf '%b' "$(sed 's/../\\x&/g' <<<"${ssid#=}")")
    fi
    passphrase=$(sed -n 's/^Passphrase=//p' "$psk")
    [[ -n "$passphrase" ]] || continue
    # the home rule needs the hardware mac there, every other wifi gets NetworkManager.conf's random one
    cloned_mac=""
    [[ -z "$HOME_GATEWAY" || "$ssid" != "$HOME_SSID" ]] || cloned_mac=$'\ncloned-mac-address=permanent'
    # the ssid as its bytes (a ;-separated list), which needs no escaping at all
    install -Dm600 /dev/stdin "$MOUNT/etc/NetworkManager/system-connections/$name.nmconnection" <<NM
[connection]
id=$(keyfile_escape "$ssid")
type=wifi

[wifi]
ssid=$(printf '%s' "$ssid" | od -An -tu1 -v | xargs printf '%s;')$cloned_mac

[wifi-security]
key-mgmt=wpa-psk
psk=$(keyfile_escape "$passphrase")

[ipv4]
method=auto

[ipv6]
method=auto
NM
done

# the new machine's home, machine-local: no secret ever removes it (option C)
[[ -z "$HOME_GATEWAY" ]] || install -Dm644 /dev/stdin "$MOUNT$HOME_GATEWAYS" <<<"$HOME_GATEWAY"

# --- dotfiles and the stage chain ---------------------------------------------

# a profile with secrets: pull and unlock them here (the one tap window), so the chained config boot needs no touch
if profile_has secrets; then
    pacman -Sy --noconfirm --needed age age-plugin-yubikey git-crypt pcsclite ccid libfido2 yubikey-manager \
        || echo "bootstrap: secrets toolchain install failed, config will unlock instead" >&2
    systemctl start pcscd.socket 2>/dev/null || true
    ( cd "$REPO" && DOTFILES="$REPO" ./scripts/lib/yubikey.sh unlock ) || echo "bootstrap: secrets unlock skipped" >&2
fi

user_setup

install -Dm644 /dev/stdin "$MOUNT$STAGE_STATE_DIR/next" <<<"install"
install -Dm644 /dev/stdin "$MOUNT$STAGE_STATE_DIR/luks-device" <<<"/dev/disk/by-uuid/$LUKS_UUID"
# verifypw=any: with %wheel still asking, `sudo -v` would want a password despite the NOPASSWD rule
printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\nDefaults:%s verifypw=any\n' "$USERNAME" "$USERNAME" \
    | install -Dm440 /dev/stdin "$MOUNT/etc/sudoers.d/zz-dotfiles-stage"
# PAMName gives the stages a logind session, so user units and dbus work like after a login
install -Dm644 /dev/stdin "$MOUNT/etc/systemd/system/dotfiles-stage.service" <<UNIT
[Unit]
Description=arch-dotfiles install chain (stage.sh)
Wants=network-online.target
After=network-online.target
ConditionPathExists=$STAGE_STATE_DIR/next

[Service]
# not oneshot: multi-user.target would wait for the whole stage, and a link.sh restarting a unit ordered after multi-user.target (tlp) then deadlocks
Type=exec
User=$USERNAME
PAMName=login
WorkingDirectory=/home/$USERNAME/projects/arch-dotfiles
ExecStart=/home/$USERNAME/projects/arch-dotfiles/stage.sh
# a tty, not journal+console, so install.sh re-execs under script and pacman draws its bars; install.log keeps the output
StandardOutput=tty
TimeoutStartSec=infinity

[Install]
WantedBy=multi-user.target
UNIT
arch-chroot "$MOUNT" systemctl enable dotfiles-stage.service

umount -R "$MOUNT"
cryptsetup close "$LUKS_NAME"
echo "bootstrap: done, rebooting in $REBOOT_DELAY_S s; remove the ISO. the next boots run install.sh and config.sh by themselves"
sleep "$REBOOT_DELAY_S"
reboot
