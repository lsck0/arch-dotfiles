# shellcheck shell=bash
# runs on the test vm's guest as root, fetched by dot test (scripts/lib/vm.nu); @KEY@ placeholders are filled in there
kver=$(uname -r)
say kver_old "$kver"
if [[ "$kver" != @KVER_NEW@ && -d "/usr/lib/modules/$kver" ]]; then say booted_old yes; else say booted_old no; fi
# in @, so the snapshot keeps it; its twin made after must be gone once the snapshot is back
touch /etc/drill-rollback-before
tag="drill-rollback-$(date +%s)"
timeshift --create --scripted --comments "$tag"
snap=$(timeshift --list --scripted | grep -F "$tag" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}' | head -1)
say snapshot "${snap:-none}"
say snapshot_made "$(yesno test -n "$snap")"
rm -f /etc/drill-rollback-before
touch /etc/drill-rollback-after
# the bump: the esp gets the newer kernel and its uki, the snapshot keeps the older modules
pacman -S --noconfirm @PKGBASE@
now=$(pacman -Q @PKGBASE@ | cut -d' ' -f2)
say bumped "$(yesno test "$now" = @KERNEL_NEW@)"
report
[[ -z "$snap" || "$now" != @KERNEL_NEW@ ]] || systemctl reboot
