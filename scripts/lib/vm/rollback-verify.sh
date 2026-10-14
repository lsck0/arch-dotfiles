# shellcheck shell=bash
kver=$(uname -r)
say kver_running "$kver"
say pkg_version "$(pacman -Q @PKGBASE@ | cut -d' ' -f2)"
say modprobe "$(yesno modprobe dummy)"
in_step=yes
for pkgbase_file in /usr/lib/modules/*/pkgbase; do
    dir=${pkgbase_file%/*}
    [[ -f "$dir/vmlinuz" ]] || continue
    [[ "$(file -bL "/boot/vmlinuz-$(< "$pkgbase_file")")" == *", version ${dir##*/} "* ]] || in_step=no
done
say esp_in_step "$in_step"
say marker_before "$(yesno test -e /etc/drill-rollback-before)"
say marker_after "$(yesno test -e /etc/drill-rollback-after)"
# the boot before this one ran the bumped esp kernel on the restored modules, and kernel-resync rebooted out of it
resync=$(journalctl -b -1 -u kernel-resync.service -o cat --no-pager)
say resync_restored "$(yesno grep -qF 'restoring it from the installed @PKGBASE@' <<< "$resync")"
say resync_rebooted "$(yesno grep -qF 'rebooting into the restored kernel' <<< "$resync")"
say resync_result "$(systemctl show -p Result --value kernel-resync.service)"
rm -f /etc/drill-rollback-before
timeshift --delete --snapshot @SNAPSHOT@ --scripted
report
