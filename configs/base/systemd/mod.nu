use module.nu *
export use ../boot/boot.nu [cmdline-set]

export const meta = {packages: {pacman: [nss-mdns], native: [bluez bluez-obex bluez-utils thermald]}, volatile: true}

const KBD_DROPIN = "systemd-backlight@.service"
const AVAHI_ALIAS = "/etc/systemd/system/dbus-org.freedesktop.Avahi.service"
# unused (luks binds pcr 7+15, cryptenroll makes the srk); systemd 258 fails them on a tpm without nvpcr indices
const TPM_UNUSED = [systemd-pcrproduct.service systemd-pcrlogin@.service systemd-tpm2-setup-early.service]

def present [unit: string]: nothing -> bool {
    let name = $unit | str replace --regex '^([^@]+@).*(\.[a-z]+)$' '$1$2'
    let layer = $env.DOT_LAYER? | default user
    ^systemctl $"--($layer)" list-unit-files --no-legend $name | complete | get stdout | str trim | is-not-empty
}

def if-present [unit: string, decl: closure]: nothing -> any {
    if (present $unit) { do $decl } else { [] }
}

export def system [cfg: record] {
    [
        (if-present proton.VPN.service { unit-disable proton.VPN.service })
        (if-present avahi-daemon.socket { unit-enable avahi-daemon.socket })
        (if-present avahi-daemon.service {
            file-link /usr/lib/systemd/system/avahi-daemon.service $AVAHI_ALIAS
        })
        (if-present bluetooth.service { unit-enable bluetooth.service })
        (if-present bluetooth.service { ini-merge /etc/bluetooth/main.conf {Policy: {AutoEnable: "false"}} })
        (if-present cups.socket { unit-enable cups.socket })
        (if-present paccache.timer { unit-enable paccache.timer --now })
        (if-present fstrim.timer { unit-enable fstrim.timer })
        (if (open --raw /proc/cpuinfo | str contains GenuineIntel) {
            if-present thermald.service { unit-enable thermald.service }
        } else { [] })
        (if-present NetworkManager-wait-online.service { unit-mask NetworkManager-wait-online.service })
        (if-present systemd-binfmt.service { unit-mask systemd-binfmt.service })
        ($TPM_UNUSED | each {|u| if-present $u { unit-mask $u } })
        # the initrd copies the unit from /usr/lib without the /etc mask, so mask it there too
        (if $env.FORM_FACTOR? == "wsl" { [] } else {
            step cmdline-set rd.systemd.mask=systemd-tpm2-setup-early.service
        })
        (if $env.FORM_FACTOR? == "laptop" { dropin $KBD_DROPIN kbd-backlight.conf } else { [] })
        (file-copy user-stop-timeout.conf /etc/systemd/user.conf.d/10-stop-timeout.conf)
        # the user preset enables these but arch never applies user presets, so they are linked as --global enable would
        (if-present systemd-tmpfiles-setup.service {
            file-link /usr/lib/systemd/user/systemd-tmpfiles-setup.service /etc/systemd/user/basic.target.wants/systemd-tmpfiles-setup.service
        })
        (if-present systemd-tmpfiles-clean.timer {
            file-link /usr/lib/systemd/user/systemd-tmpfiles-clean.timer /etc/systemd/user/timers.target.wants/systemd-tmpfiles-clean.timer
        })
    ] | decls-flatten
}

export def link [cfg: record] {
    let keyring = present gnome-keyring-daemon.service
    [
        ([gnome-keyring-daemon.service gnome-keyring-daemon.socket] | each {|u| if-present $u { unit-mask $u --now } })
        # its secrets component waits for --start, which gnome's OnlyShowIn=GNOME autostart entry would send
        (if $keyring { unit-file keyring-secrets.service --enable } else { [] })
        ([pipewire-pulse.service pipewire-pulse.socket ssh-agent.service]
            | each {|u| if-present $u { unit-enable $u } })
    ] | decls-flatten
}
