#!/usr/bin/env bash
# Manually install or remove one or more package groups after the fact, "at
# your own risk" per the design note this implements — install.sh's own
# group filtering only ever runs once, at install time. Reads group tags
# straight out of install.sh's own PACKAGES/CARGO_PKGS/GO_PKGS array source
# (each entry is commented `# [group] description`), so it always matches
# whatever install.sh would have installed for that group.
#
# Usage: groups-apply.sh install|remove <group> [<group>...]
set -euo pipefail

INSTALL_SH="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)/install.sh"
KNOWN_GROUPS="base desktop programming security creating socials gaming misc"

usage() {
    echo "Usage: $(basename "$0") install|remove <group> [<group>...]" >&2
    echo "Known groups: $KNOWN_GROUPS" >&2
    exit 1
}

[[ $# -ge 2 ]] || usage
action="$1"; shift
[[ "$action" == "install" || "$action" == "remove" ]] || usage

for g in "$@"; do
    [[ " $KNOWN_GROUPS " == *" $g "* ]] || { echo "Unknown group: $g" >&2; usage; }
done

# Pull every pacman/AUR package tagged with one of the requested groups out
# of install.sh's PACKAGES array source (comments never survive into a bash
# array at runtime, so this greps the file text itself, not the array).
# Plain substring match on "[groupname]" — deliberately not a regex (an
# unescaped literal `[` in a dynamic awk regex opens a bracket expression,
# which silently turned this into "match almost any line" the first time
# this was written; caught in testing, not left in).
pkgs=$(awk -v groups="$*" '
    BEGIN { n = split(groups, g, " ") }
    /^PACKAGES=\(/ {f=1; next}
    f && /^\)/ {f=0}
    f {
        for (i = 1; i <= n; i++) {
            if (index($0, "[" g[i] "]") > 0) {
                pkg=$1; gsub(/^[ \t]+|[ \t]+$/, "", pkg)
                if (pkg != "") print pkg
                break
            }
        }
    }
' "$INSTALL_SH")

if [[ -z "$pkgs" ]]; then
    echo "No packages tagged with group(s): $* — nothing to do." >&2
    exit 0
fi

echo "Packages in group(s) [$*]:" >&2
printf '  %s\n' $pkgs >&2
read -rp "Proceed to $action these with yay? [y/N] " confirm
[[ "$confirm" == [yY]* ]] || { echo "Aborted." >&2; exit 1; }

# Revert a link.sh's systemd/cron side effects for a package that's about to
# be uninstalled. Without this, `yay -Rns` removes the binary but leaves
# every enabled unit/cron entry a corresponding configs/*/link.sh created
# still enabled — a fail2ban.service that's "enabled" with no
# fail2ban-client on disk fails at every boot, a cron.daily entry calling a
# removed binary fails silently every day, forever, until someone notices
# and hand-diagnoses it. One table here, reviewed once, beats scattering
# uninstall-time revert logic across 14 individually-guarded link.sh files.
# Only lists packages that HAVE such a side effect — most packages in
# PACKAGES have none and need no entry. `|| true` throughout: a unit that
# was never enabled, or a symlink already gone, is not an error here.
revert_package_side_effects() {
    local pkg="$1"
    case "$pkg" in
        fail2ban)
            sudo systemctl disable fail2ban.service 2>/dev/null || true
            sudo rm -f /etc/fail2ban/jail.local
            ;;
        elan-lean)
            # elan has no self-uninstall; remove the toolchain dir and the
            # binary the package manager no longer tracks.
            rm -rf "${HOME}/.elan"
            ;;
        docker)
            sudo systemctl disable docker.socket 2>/dev/null || true
            sudo rm -f /etc/cron.daily/docker-prune-job
            ;;
        trash-cli)
            sudo rm -f /etc/cron.daily/trash-clean-job
            ;;
        tlp)
            sudo systemctl disable tlp.service 2>/dev/null || true
            sudo rm -f /etc/tlp.conf
            ;;
        cups)
            sudo systemctl disable cups.socket cups.service 2>/dev/null || true
            ;;
        openssh)
            sudo systemctl disable sshd 2>/dev/null || true
            rm -f "${HOME}/.config/systemd/user/ssh-agent.service"
            ;;
        ghostmirror)
            # Deliberately does NOT remove /etc/pacman.d/mirrorlist itself —
            # that file is just a list of URLs pacman reads regardless of
            # whether ghostmirror is installed; only the maintenance
            # timers depend on the package.
            systemctl --user disable ghostmirror.timer ghostmirror-refresh.timer 2>/dev/null || true
            rm -f "${HOME}/.config/systemd/user/ghostmirror.service" \
                  "${HOME}/.config/systemd/user/ghostmirror.timer" \
                  "${HOME}/.config/systemd/user/ghostmirror-refresh.service" \
                  "${HOME}/.config/systemd/user/ghostmirror-refresh.timer"
            ;;
        cifs-utils)
            sudo systemctl disable mnt-homelab.automount 2>/dev/null || true
            sudo rm -f /etc/systemd/system/mnt-homelab.mount /etc/systemd/system/mnt-homelab.automount
            ;;
        python-validity-git)
            sudo systemctl disable python3-validity.service 2>/dev/null || true
            sudo rm -rf /etc/systemd/system/python3-validity.service.d
            ;;
        bluez)
            sudo systemctl disable bluetooth.service 2>/dev/null || true
            ;;
        cronie)
            sudo systemctl disable cronie.service 2>/dev/null || true
            ;;
        ly)
            sudo systemctl disable ly@tty2.service 2>/dev/null || true
            ;;
        thermald)
            sudo systemctl disable thermald.service 2>/dev/null || true
            ;;
        ossec-hids-local)
            sudo systemctl disable ossec-server.target 2>/dev/null || true
            ;;
        pacman-contrib)
            sudo systemctl disable paccache.timer 2>/dev/null || true
            ;;
        zram-generator)
            sudo rm -f /etc/systemd/zram-generator.conf /etc/sysctl.d/99-zram.conf
            ;;
        polkit)
            systemctl --user disable timezone-auto.timer 2>/dev/null || true
            sudo rm -f /etc/polkit-1/rules.d/49-timezone-auto.rules
            rm -f "${HOME}/.config/systemd/user/timezone-auto.service" \
                  "${HOME}/.config/systemd/user/timezone-auto.timer"
            ;;
        # python-vllm-rocm is deliberately absent here: it is never
        # installed via install.sh's PACKAGES array (this function only
        # ever sees packages that came from that array's group tags — see
        # the awk extraction above), so it can never be uninstalled through
        # groups-apply.sh in the first place. It's installed and removed by
        # hand via configs/vllm/link.sh's own `yay -S`, on a real ROCm GPU
        # host only — see that script's own header comment.
    esac
}

if [[ "$action" == "install" ]]; then
    yay -S $pkgs --noconfirm --mflags --skipinteg
else
    yay -Rns $pkgs --noconfirm
    echo "Reverting systemd/cron side effects for removed packages..." >&2
    sudo systemctl daemon-reload 2>/dev/null || true
    systemctl --user daemon-reload 2>/dev/null || true
    for pkg in $pkgs; do
        revert_package_side_effects "$pkg"
    done
fi
