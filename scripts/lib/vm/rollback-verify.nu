use prelude.nu *

const MARKER_BEFORE = "/etc/drill-rollback-before"
const MARKER_AFTER = "/etc/drill-rollback-after"

say kver_running (^uname -r | str trim)
say pkg_version (package-version "@PKGBASE@")
say modprobe (succeeds { ^modprobe dummy } | yesno)
let in_step = glob /usr/lib/modules/*/pkgbase | all {|pkgbase_file|
    let dir = $pkgbase_file | path dirname
    let esp_image = $"/boot/vmlinuz-(open --raw $pkgbase_file | str trim)"
    ($dir | path join vmlinuz | path type) != file or (output { ^file -bL $esp_image } | str contains $", version ($dir | path basename) ")
}
say esp_in_step ($in_step | yesno)
say marker_before ($MARKER_BEFORE | path exists | yesno)
say marker_after ($MARKER_AFTER | path exists | yesno)
# the boot before this one ran the bumped esp kernel on the restored modules, and kernel-resync rebooted out of it
let resync = output { ^journalctl -b -1 -u kernel-resync.service -o cat --no-pager }
say resync_restored ($resync | str contains 'restoring it from the installed @PKGBASE@' | yesno)
say resync_rebooted ($resync | str contains 'rebooting into the restored kernel' | yesno)
say resync_result (output { ^systemctl show -p Result --value kernel-resync.service })
rm --force $MARKER_BEFORE
do --ignore-errors { ^timeshift --delete --snapshot "@SNAPSHOT@" --scripted }
report
