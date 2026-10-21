use module.nu *

const BOARD = "X870E AORUS ELITE WIFI7"

export def system [cfg: record] {
    let board = try { open --raw /sys/class/dmi/id/board_name | str trim } catch { "" }
    if $env.FORM_FACTOR? != "desktop" or $board != $BOARD { return [] }
    [
        (file-copy it87-modules-load.conf /etc/modules-load.d/it87.conf)
        (file-copy it87-modprobe.conf /etc/modprobe.d/it87.conf)
        # it only loads what sensors-detect wrote, which never runs here; modules-load has it87
        (unit-disable lm_sensors.service)
        (file-copy gen-fancontrol.nu /usr/local/bin/gen-fancontrol --mode 755)
        (dropin fancontrol.service fancontrol-regen.conf --name regen.conf)
        (unit-file fancontrol-gen.service --enable)
        (unit-enable fancontrol.service --now)
    ]
}
