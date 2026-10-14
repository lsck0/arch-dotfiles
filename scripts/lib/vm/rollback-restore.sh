# shellcheck shell=bash
kver=$(uname -r)
say kver_bumped "$kver"
say esp_kver "$(file -bL /boot/vmlinuz-@PKGBASE@ | grep -oP 'version \K\S+')"
report
[[ "$kver" == @KVER_NEW@ ]] || exit 0
# timeshift reboots on its own once @ is swapped; the reboot below covers a run that returns instead
timeshift --restore --snapshot @SNAPSHOT@ --scripted --yes --skip-grub
say restore_rc "$?"
report
systemctl reboot
