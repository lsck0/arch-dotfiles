use module.nu *

export const meta = {packages: {native: [btrfs-progs timeshift timeshift-autosnap]}}

const CONF = "/etc/timeshift/timeshift.json"
# the timer is the schedule, cronie only came as a dependency
const CRON_JOBS = [/etc/cron.d/timeshift-hourly /etc/cron.d/timeshift-boot]
const SCHEDULE = {
    do_first_run: "false", btrfs_mode: "true"
    include_btrfs_home_for_backup: "false", include_btrfs_home_for_restore: "false"
    schedule_weekly: "true", schedule_monthly: "false", schedule_daily: "false", schedule_hourly: "false"
    count_weekly: "4", count_monthly: "0", count_daily: "0", count_hourly: "0"
    date_format: "%Y-%m-%d_%H-%M-%S"
}

def root-mount [field: string]: nothing -> string {
    ^findmnt -n -o $field / | str trim
}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    let fstype = root-mount FSTYPE
    # btrfs mode needs root on a named subvolume such as @
    if $fstype != "btrfs" or (root-mount OPTIONS) =~ 'subvolid=5\b' or (root-mount FSROOT) in ["/" ""] {
        return []
    }
    let uuid = root-mount UUID
    if $uuid == "" { error make {msg: "timeshift: no UUID for the root device"} }
    [
        (unit-disable cronie.service --now)
        # merged: timeshift rewrites the file with its own keys
        (json-merge $CONF ($SCHEDULE | insert backup_device_uuid $uuid | items {|k, v| json-set [$k] $v }))
        (file-copy timeshift-autosnap.conf /etc/timeshift-autosnap.conf)
        (unit-file timeshift-check.service)
        (unit-file timeshift-check.timer --enable --now)
        (exec "timeshift check" [timeshift --check --scripted])
        (exec "drop timeshift cron jobs" [rm -f ...$CRON_JOBS])
    ] ++ (if (^stat -f -c %T /boot | str trim) != "msdos" { [] } else {
        # a restored @ boots the esp's newer kernels against its older modules (ROLLBACK.md)
        [
            (file-copy esp-vfat.conf /etc/mkinitcpio.conf.d/10-esp-vfat.conf)
            (file-copy kernel-resync.nu /usr/local/bin/kernel-resync --mode 755)
            (unit-file kernel-resync.service --enable)
        ]
    })
}
