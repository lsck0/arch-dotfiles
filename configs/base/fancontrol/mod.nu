use module.nu *
use scripts/gen-fancontrol.nu [BOARD BOARD_NAME_FILE]

export def system [cfg: record] {
    if $env.FORM_FACTOR? != "desktop" or (file-trim $BOARD_NAME_FILE) != $BOARD { return [] }
    [
        # both sensors before fancontrol-gen (After=systemd-modules-load): k10temp's udev coldplug may come later
        (file-copy config/modules-load.conf /etc/modules-load.d/fancontrol.conf)
        (file-copy config/it87-modprobe.conf /etc/modprobe.d/it87.conf)
        # it only loads what sensors-detect wrote, which never runs here; modules-load has it87
        (unit-disable lm_sensors.service)
        (file-copy scripts/gen-fancontrol.nu /usr/local/bin/gen-fancontrol --mode 755)
        (dropin fancontrol.service config/fancontrol-regen.conf --name regen.conf)
        (unit-file config/fancontrol-gen.service --enable)
        (unit-enable fancontrol.service --now)
    ]
}
