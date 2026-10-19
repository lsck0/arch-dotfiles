use module.nu *

# force_id and the fan curve fit exactly this board and its 9950X3D
const BOARD = "X870E AORUS ELITE WIFI7"

export def system [cfg: record] {
    let board = try { open --raw /sys/class/dmi/id/board_name | str trim } catch { "" }
    if $env.FORM_FACTOR? != "desktop" or $board != $BOARD { return [] }
    [
        (file-copy it87-modules-load.conf /etc/modules-load.d/it87.conf)
        (file-copy it87-modprobe.conf /etc/modprobe.d/it87.conf)
        # its oneshot only loads what sensors-detect wrote to /etc/conf.d/lm_sensors, never run here; modules-load has it87
        (unit-disable lm_sensors.service)
        # fancontrol keeps ProtectSystem=full, so the regen is a unit of its own
        (file-copy gen-fancontrol.nu /usr/local/bin/gen-fancontrol --mode 755)
        (dropin fancontrol.service fancontrol-regen.conf --name regen.conf)
        (unit-file fancontrol-gen.service --enable)
        (unit-enable fancontrol.service --now)
    ]
}
