use prelude.nu *

const MARKER_BEFORE = "/etc/drill-rollback-before"
const MARKER_AFTER = "/etc/drill-rollback-after"

let kver = ^uname -r | str trim
say kver_old $kver
say booted_old ($kver != "@KVER_NEW@" and ($"/usr/lib/modules/($kver)" | path type) == dir | yesno)
touch $MARKER_BEFORE
let tag = $"drill-rollback-(date now | format date '%s')"
do --ignore-errors { ^timeshift --create --scripted --comments $tag }
let snap = output { ^timeshift --list --scripted }
    | lines
    | where ($it | str contains $tag)
    | parse --regex '(?<s>\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})'
    | get --optional 0.s
say snapshot ($snap | default none)
say snapshot_made ($snap != null | yesno)
rm --force $MARKER_BEFORE
touch $MARKER_AFTER
# the esp gets the newer kernel and uki, the snapshot keeps the older modules
do --ignore-errors { ^pacman -S --noconfirm "@PKGBASE@" }
let bumped = (package-version "@PKGBASE@") == "@KERNEL_NEW@"
say bumped ($bumped | yesno)
report
if $snap != null and $bumped { ^systemctl reboot }
