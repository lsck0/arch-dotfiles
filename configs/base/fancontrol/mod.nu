use module.nu *

const BOARD = "X870E AORUS ELITE WIFI7"

export def system [cfg: record] {
    let board = try { open --raw /sys/class/dmi/id/board_name | str trim } catch { "" }
    if $env.FORM_FACTOR? != "desktop" or $board != $BOARD { return [] }
    [
        # both sensors before fancontrol-gen (After=systemd-modules-load): k10temp's udev coldplug may come later
        (file-copy modules-load.conf /etc/modules-load.d/fancontrol.conf)
        (file-copy it87-modprobe.conf /etc/modprobe.d/it87.conf)
        # it only loads what sensors-detect wrote, which never runs here; modules-load has it87
        (unit-disable lm_sensors.service)
        (file-copy gen-fancontrol.nu /usr/local/bin/gen-fancontrol --mode 755)
        (dropin fancontrol.service fancontrol-regen.conf --name regen.conf)
        (unit-file fancontrol-gen.service --enable)
        (unit-enable fancontrol.service --now)
    ]
}
