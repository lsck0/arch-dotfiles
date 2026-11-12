use module.nu *
export use ../boot/boot.nu [cmdline-set]

export const meta = {packages: {pacman: [nss-mdns], native: [bluez bluez-obex bluez-utils thermald]}, volatile: true}

export const options = {
    mem_sleep: {
        type: string?
        default: null
        choices: [s2idle deep]
        doc: "Suspend mode written to /sys/power/mem_sleep; unset, the firmware's default"
        label: "Suspend mode"
        scope: machine
        apply: live
    }
}

const KBD_DROPIN = "systemd-backlight@.service"
const AVAHI_ALIAS = "/etc/systemd/system/dbus-org.freedesktop.Avahi.service"
# unused (luks binds pcr 7+15, cryptenroll makes the srk); systemd 258 fails them on a tpm without nvpcr indices
const TPM_UNUSED = [systemd-pcrproduct.service systemd-pcrlogin@.service systemd-tpm2-setup-early.service]

def if-present [unit: string, decl: closure]: nothing -> any {
    if (unit-installed $unit) { do $decl } else { [] }
}

export def system [cfg: record] {
    [
        (if-present proton.VPN.service { unit-disable proton.VPN.service })
        (if-present avahi-daemon.socket { unit-enable avahi-daemon.socket })
        (if-present avahi-daemon.service { file-link /usr/lib/systemd/system/avahi-daemon.service $AVAHI_ALIAS })
        # geoclue looks for gps sources over avahi, which stays off away from home: each lookup fails an activation
        (if-present geoclue.service {[
            (file-text /etc/geoclue/conf.d/90-no-network-nmea.conf "[network-nmea]\nenable=false\n")
            (dropin geoclue.service geoclue-startup.conf --name 10-startup.conf)
        ]})
        (if-present bluetooth.service {[
            (unit-enable bluetooth.service) (ini-merge /etc/bluetooth/main.conf {Policy: {AutoEnable: "false"}})
        ]})
        (if-present cups.socket { unit-enable cups.socket })
        (if-present paccache.timer { unit-enable paccache.timer --now })
        (if-present fstrim.timer { unit-enable fstrim.timer })
        (if (open --raw /proc/cpuinfo | str contains GenuineIntel) and (unit-installed thermald.service) {
            unit-enable thermald.service
        })
        ([NetworkManager-wait-online.service systemd-binfmt.service ...$TPM_UNUSED] | each {|u| if-present $u { unit-mask $u } })
        # the initrd copies the unit from /usr/lib without the /etc mask, so mask it there too
        (if $env.FORM_FACTOR? != "wsl" {
            step cmdline-set rd.systemd.mask=systemd-tpm2-setup-early.service
        })
        (if $env.FORM_FACTOR? == "laptop" { dropin $KBD_DROPIN kbd-backlight.conf })
        (file-copy user-stop-timeout.conf /etc/systemd/user.conf.d/10-stop-timeout.conf)
        (if $cfg.mem_sleep != null {
            file-text /etc/systemd/sleep.conf.d/10-mem-sleep.conf $"[Sleep]\nMemorySleepMode=($cfg.mem_sleep)\n"
        })
        # the user preset enables these but arch never applies user presets, so they are linked as --global enable would
        ([[systemd-tmpfiles-setup.service basic.target] [systemd-tmpfiles-clean.timer timers.target]] | each {|u|
            if-present $u.0 { file-link $"/usr/lib/systemd/user/($u.0)" $"/etc/systemd/user/($u.1).wants/($u.0)" }
        })
    ]
}

export def link [cfg: record] {
    let keyring = which gnome-keyring-daemon | is-not-empty
    [
        ([gnome-keyring-daemon.service gnome-keyring-daemon.socket] | each {|u| if-present $u { unit-mask $u --now } })
        # its secrets component waits for --start, which gnome's OnlyShowIn=GNOME autostart entry would send
        (if $keyring { unit-file keyring-secrets.service --enable })
        ([pipewire-pulse.service pipewire-pulse.socket] | each {|u| if-present $u { unit-enable $u } })
    ]
}
