# shellcheck shell=bash
# the ledger: what the dotfiles own, one scope per file. the machine ledger (root, written only by system-apply) holds
# `pkg <name>`, `unit system <name>` and `snapshot <pin|latest> <db time> <db sha256>` for the lsck0 snapshot last
# installed from; a user's holds `unit user <name>`. only an owned entry the repo stopped declaring is ever removed, and
# only after the exact list was shown and confirmed at /dev/tty (stdin may carry the secrets tar); an unattended run
# reports and keeps everything. what a person installed or enabled by hand is drift: reported, never touched. outside
# git like patches-applied, so a fresh machine starts empty and owns its declared set on the first run, which therefore
# removes nothing but LEDGER_PACKAGES_SEED.

source "$(dirname "${BASH_SOURCE[0]}")/system.sh"

if ((EUID == 0)); then
    LEDGER_SCOPE=system
    LEDGER_FILE="$SYSTEM_STATE/ledger"
else
    LEDGER_SCOPE=user
    LEDGER_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/ledger"
fi
# never removed, whatever the lists say: base, kernels, firmware, microcode, the boot chain and what repairs the rest,
# plus the yubikey/fido2 unlock chain and sshd, so a dropped-package confirmation can never lock the machine out
LEDGER_PACKAGES_DENY='base|base-devel|linux.*|.*-firmware|.*-ucode|grub|efibootmgr|sbctl|cryptsetup|btrfs-progs|mkinitcpio|systemd.*|networkmanager|sudo|pacman|git|gnupg|yay|nix|libfido2|openssh|age|age-plugin-yubikey|git-crypt|pcsclite'
# dropped from install.sh before the ledger existed (generation 487, formerly patches 02 and 04): a machine's first run
# owns the ones still installed, so they are proposed like any dropped package; delete once every machine has a ledger
LEDGER_PACKAGES_SEED=(
    betterdiscord-installer betterdiscordctl-git blueberry bootimage burpsuite cargo-machete cargo-watch
    cargo-xbuild easyeffects glava gufw hyprsunset iwd libva-intel-driver mise neofetch neovim-remote
    opentabletdriver-git opentofu python-black python-isort usage virt-manager wireless_tools xf86-input-synaptics
    xf86-video-amdgpu xf86-video-ati xf86-video-nouveau
)
# a unit name systemctl accepts; one invalid name fails the whole batched is-enabled
LEDGER_UNIT_NAME='[A-Za-z0-9][A-Za-z0-9:_.-]*(@[A-Za-z0-9:_.-]*)?\.(service|socket|timer|path|mount|automount|target)'

# ledger_get <kind>: the names of one kind (pkg, unit, snapshot), sorted, one per line
ledger_get() {
    sed -n "s/^$1 //p" "$LEDGER_FILE" 2>/dev/null | sort
}

# ledger_set <kind>: stdin replaces the names of <kind>; renamed into place, so a crash keeps the old ledger
ledger_set() {
    mkdir -p "${LEDGER_FILE%/*}"
    { grep -v "^$1 " "$LEDGER_FILE" 2>/dev/null || true; sed "/^$/d; s/^/$1 /"; } | sort -u >"$LEDGER_FILE.new"
    mv -f "$LEDGER_FILE.new" "$LEDGER_FILE"
}

# ledger_confirm <verb> <entry...>: show the exact list; yes only from a person at the tty, unattended keeps everything
ledger_confirm() {
    local verb="$1" answer
    shift
    (($#)) || return 1
    echo "ledger: owned but no longer declared, to $verb:" >&2
    printf '  %s\n' "$@" >&2
    if [[ -n "${DOTFILES_UNATTENDED:-}" ]] || ! { : </dev/tty; } 2>/dev/null; then
        echo "ledger: unattended, nothing done; rerun at a terminal to $verb them" >&2
        return 1
    fi
    read -rp "ledger: $verb these $#? [y/N] " answer </dev/tty || return 1
    [[ "$answer" == y ]]
}

# ledger_packages <declared...>: own what install.sh lists, remove what it owned and stopped listing, report the rest
ledger_packages() {
    local -a declared owned dropped orphans drift
    # by installed name, a provide (sh) owns bash and a group (texlive) its members; each exits 1 on an unknown name
    mapfile -t declared < <({ pacman -Qq "$@" || true; pacman -Qqg "$@" || true; } 2>/dev/null | sort -u)
    # an empty declared set would turn every owned package into a dropped one
    ((${#declared[@]})) || { echo "ledger: none of the $# listed packages is installed, refusing" >&2; return 1; }
    mapfile -t owned < <(ledger_get pkg)
    ((${#owned[@]})) || owned=("${LEDGER_PACKAGES_SEED[@]}")
    mapfile -t dropped < <(comm -12 <(pacman -Qq | sort) <(printf '%s\n' "${owned[@]}" | sort -u) \
        | comm -23 - <(printf '%s\n' "${declared[@]}") | grep -vxE "$LEDGER_PACKAGES_DENY")
    if ledger_confirm remove "${dropped[@]}"; then
        # listed ones explicit first, so -s never takes one only a dropped package had pulled in
        pacman -D --asexplicit "${declared[@]}" >/dev/null || return 1
        # reversible first: whatever another package still requires stays as a dependency, only orphans leave
        pacman -D --asdeps "${dropped[@]}" >/dev/null || return 1
        mapfile -t orphans < <(pacman -Qdttq | sort | comm -12 - <(printf '%s\n' "${dropped[@]}"))
        ((${#orphans[@]} == 0)) || pacman -Rns --noconfirm "${orphans[@]}" || return 1
        dropped=()
    fi
    printf '%s\n' "${declared[@]}" "${dropped[@]}" | ledger_set pkg
    mapfile -t drift < <(pacman -Qqe | sort | comm -23 - <(ledger_get pkg))
    ((${#drift[@]} == 0)) || echo "ledger: installed by hand, not managed: ${drift[*]}" >&2
}

# ledger_units <repo>: own every enabled unit of this scope the repo names, disable an owned one it stopped naming, report the rest
ledger_units() {
    local repo="$1" scope="$LEDGER_SCOPE" i also units path
    local -a declared names states paths=() owned=() dropped=()
    # only this platform's groups declare, so a dropped group's units get disabled; a unit named in any comment here would
    # declare. a plain grep, the root copy has no .git; install.sh and config.sh are not in it. fails, never empty
    for path in "${PKG_GROUPS[@]/#/configs/}" scripts install.sh config.sh; do
        if [[ -e "$repo/$path" ]]; then paths+=("$repo/$path"); fi
    done
    units=$(grep -rhoIE "$LEDGER_UNIT_NAME" --exclude='*.log' -- "${paths[@]}") \
        || { echo "ledger: grep for unit names failed in $repo" >&2; return 1; }
    mapfile -t declared < <(sort -u <<<"$units")
    mapfile -t names < <({ printf '%s\n' "${declared[@]}"; ledger_get unit | sed -n "s/^$scope //p"; } \
        | grep -xE "$LEDGER_UNIT_NAME" | sort -u)
    mapfile -t states < <(systemctl --"$scope" is-enabled "${names[@]}" 2>/dev/null)
    if ((${#states[@]} != ${#names[@]})); then
        echo "ledger: systemctl --$scope is-enabled answered ${#states[@]} of ${#names[@]} units" >&2
        return 1
    fi
    for i in "${!names[@]}"; do
        [[ "${states[i]}" == enabled ]] || continue
        if [[ " ${declared[*]} " == *" ${names[i]} "* ]]; then owned+=("${names[i]}"); else dropped+=("${names[i]}"); fi
    done
    if ledger_confirm disable "${dropped[@]}"; then
        systemctl --"$scope" disable --now "${dropped[@]}" || return 1
        dropped=()
    fi
    printf '%s\n' "${owned[@]}" "${dropped[@]}" | sed "/^$/d; s/^/$scope /" | ledger_set unit
    # enabled against the vendor preset, neither owned nor pulled in by an owned unit's Also=: a person's
    also=" $(ledger_get unit | sed -n "s/^$scope //p" | xargs -r systemctl --"$scope" cat 2>/dev/null | sed -n 's/^Also=//p' | tr '\n' ' ') "
    systemctl --"$scope" list-unit-files --state=enabled --no-legend \
        | awk -v scope="$scope" -v also="$also" '$3 != "enabled" && !index(also, " " $1 " ") { print scope " " $1 }' \
        | sort | comm -23 - <(ledger_get unit) | sed 's/^/ledger: enabled by hand, not managed: /' >&2
}
