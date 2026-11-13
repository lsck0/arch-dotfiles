# Remote LUKS unlock: tinyssh in a mkinitcpio-systemd-tool initramfs, reached over ethernet or the home wifi.

use module.nu *
use ../boot.nu [cmdline-set cmdline-unset hooks-read hooks-write hooks-insert CMDLINE MKINITCPIO]

export const options = {
    ssh_unlock: {
        type: bool
        default: false
        doc: "Wake-on-lan this machine, then ssh into the initramfs to unlock LUKS remotely"
        label: "Remote unlock"
        apply: reboot
    }
    wifi: {
        type: bool
        default: false
        doc: "Also join the home wifis (configs/secrets/keys/wifi) in the initramfs; their keys are written into the image"
        label: "Remote unlock over wifi"
        apply: reboot
    }
}

export const meta = {
    volatile: true
    deps: [base/boot/luks]
    secrets: [wifi ssh_publickey.asc "initramfs-ssh/{host}/sshkeydir/.ed25519.sk"]
}

const PACKAGES = [busybox mkinitcpio-systemd-tool tinyssh tinyssh-convert]
const HOOK = "systemd-tool"
const TOOL_DIR = "/etc/mkinitcpio-systemd-tool"
const AUTHORIZED_KEYS = $"($TOOL_DIR)/config/authorized_keys"
const KEYDIR = "/etc/tinyssh/sshkeydir"
const UNITS = [initrd-network.service initrd-tinysshd.service]
const HOOK_INSTALL = $"/usr/lib/initcpio/install/($HOOK)"
# tinyssh's secret key is the 32-byte seed, then the public key
const ED25519_SEED_BYTES = 32
const ED25519_SK_BYTES = 64
const WIFI_UNIT = "initrd-wifi.service"
const WIFI_CONF = $"($TOOL_DIR)/config/initrd-wifi.conf"
const NEEDNET = "rd.neednet=1"

export def packages [cfg: record]: nothing -> record {
    {native: (if $cfg.ssh_unlock { $PACKAGES } else { [] })}
}

export def system [cfg: record] {
    if not $cfg.ssh_unlock {
        # the package may be gone first; its leftovers (wifi psks, authorized_keys, rd.neednet) still go
        if not (teardown-needed [$HOOK_INSTALL $WIFI_CONF $AUTHORIZED_KEYS] $CMDLINE) { return [] }
        return ($UNITS | append $WIFI_UNIT | each { unit-disable $in } | append (step teardown))
    }
    if (which tinysshd | is-empty) or not ($HOOK_INSTALL | path exists) { return [] }
    [
        (step keys)
        (file-copy mkinitcpio-systemd-tool.conf $"($TOOL_DIR)/mkinitcpio-systemd-tool.conf")
        # the stock file matches eth* only
        (file-copy initrd-network.network $"($TOOL_DIR)/network/initrd-network.network")
        (dropin initrd-tinysshd.service tinysshd.conf)
        (dropin initrd-network.service initrd-network.conf)
        # the systemd-tool hook puts enabled units in the image, ConditionPathExists keeps them off the real system
        ($UNITS | each { unit-enable $in })
        (wifi $cfg.wifi)
        (step wire)
    ]
}

# Whether any of the files exists or the kernel cmdline file still carries rd.neednet=1.
export def teardown-needed [files: list<path>, cmdline: path]: nothing -> bool {
    ($files | any { path exists }) or (
        ($cmdline | path exists) and $NEEDNET in (open --raw $cmdline | str trim | split row " "))
}

def wifi [enabled: bool]: nothing -> list {
    if not $enabled { return [(unit-disable $WIFI_UNIT) (step wifi-teardown)] }
    [
        (step wifi-conf)
        (if ($WIFI_CONF | path exists) or (system-secret wifi | path exists) {
            unit-file $WIFI_UNIT --enable
        } else { unit-disable $WIFI_UNIT })
    ]
}

# The initrd wifi config from configs/secrets/keys/wifi (ssid, tab, passphrase); without secrets, what is there stays.
export def wifi-conf []: nothing -> nothing {
    let wifi = system-secret wifi
    if not ($wifi | path exists) {
        if not ($WIFI_CONF | path exists) {
            print "note: remote-unlock: configs/secrets/keys/wifi not readable, unlock the secrets and rerun; the initramfs stays wired only"
        }
        return
    }
    let networks = open --raw $wifi | lines | where $it != "" | each {|line|
        let fields = $line | split row "\t"
        if ($fields | length) != 2 { error make {msg: "remote-unlock: configs/secrets/keys/wifi is not one ssid<tab>passphrase per line"} }
        # the passphrase goes in on stdin, never argv; wpa_passphrase's comments repeat it in plain, so they all go
        $fields.1 | ^wpa_passphrase $fields.0 | lines | where not ($it | str trim | str starts-with "#")
    } | flatten
    if not ($WIFI_CONF | path dirname | path exists) { ^install -dm700 ($WIFI_CONF | path dirname) }
    # create the file 0600 before writing the psk= lines; save --force keeps the mode of an existing file
    ^install -m600 /dev/null $WIFI_CONF
    ["ctrl_interface=/run/wpa_supplicant" ...$networks ""] | str join "\n" | save --force $WIFI_CONF
}

export def wifi-teardown []: nothing -> nothing {
    rm --force $WIFI_CONF
}

export def keys []: nothing -> nothing {
    let secret_key = host-file (system-secret initramfs-ssh) sshkeydir .ed25519.sk
    if ($secret_key | path exists) and (ls $secret_key | get 0.size | into int) == $ED25519_SK_BYTES {
        ^install -dm700 $KEYDIR
        ^install -m600 $secret_key $"($KEYDIR)/.ed25519.sk"
        open --raw $secret_key | into binary | bytes at $ED25519_SEED_BYTES.. | save --force $"($KEYDIR)/ed25519.pk"
    } else if not ($"($KEYDIR)/.ed25519.sk" | path exists) {
        ^install -dm700 ($KEYDIR | path dirname)
        ^tinysshd-makekey $KEYDIR
        let backup = host-file configs/secrets/keys/initramfs-ssh
        print ("note: remote-unlock: generated a new initramfs host key; back it up: "
            + $"mkdir -p ($backup) && sudo cp -r ($KEYDIR) ($backup)/sshkeydir && sudo chown -R $USER: ($backup)")
    }
    let pubkey = system-secret ssh_publickey.asc
    if ($pubkey | path exists) and (open --raw $pubkey | str starts-with "ssh-") {
        ^install -Dm600 $pubkey $AUTHORIZED_KEYS
    } else {
        print ("note: remote-unlock: configs/secrets/keys/ssh_publickey.asc not readable, unlock the secrets and rerun; "
            + "no authorized_keys installed")
    }
}

# Runs after sd-encrypt is placed, so the cryptsetup machinery it feeds is in place.
export def wire []: nothing -> nothing {
    if not ($AUTHORIZED_KEYS | path exists) {
        unwire
        return
    }
    let hooks = hooks-read
    if $HOOK not-in $hooks {
        let anchor = [sd-encrypt filesystems] | where $it in $hooks | get --optional 0
        if $anchor == null {
            error make {msg: "remote-unlock: no sd-encrypt or filesystems hook to anchor systemd-tool"}
        }
        hooks-write (hooks-insert $hooks $HOOK $anchor --after=($anchor == sd-encrypt))
    }
    cmdline-set $NEEDNET
}

def unwire []: nothing -> nothing {
    if ($MKINITCPIO | path exists) { hooks-write (hooks-read | where $it != $HOOK) }
    cmdline-unset rd.neednet
}

export def teardown []: nothing -> nothing {
    wifi-teardown
    rm --force $AUTHORIZED_KEYS
    unwire
}
