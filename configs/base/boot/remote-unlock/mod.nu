use module.nu *
use ../boot.nu [cmdline-set cmdline-unset hooks-read hooks-write hooks-insert MKINITCPIO]

export const options = {
    ssh_unlock: {
        type: bool
        default: false
        doc: "Wake-on-lan this machine, then ssh into the initramfs to unlock LUKS remotely"
        label: "Remote unlock"
        apply: reboot
        scope: machine
    }
    wifi: {
        type: bool
        default: false
        doc: "Also join the home wifis (secrets/wifi) in the initramfs; their keys are written into the image"
        label: "Remote unlock over wifi"
        apply: reboot
        scope: machine
    }
}

# packages are the platform's extra_packages, here they would land on every machine
export const meta = {volatile: true}

const HOOK = "systemd-tool"
const TOOL_DIR = "/etc/mkinitcpio-systemd-tool"
# never a key on the real root
const AUTHORIZED_KEYS = "/etc/mkinitcpio-systemd-tool/config/authorized_keys"
const KEYDIR = "/etc/tinyssh/sshkeydir"
const UNITS = [initrd-network.service initrd-tinysshd.service]
const HOOK_INSTALL = "/usr/lib/initcpio/install/systemd-tool"
const ED25519_SK_BYTES = 64
const WIFI_UNIT = "initrd-wifi.service"
# the image's /etc/wpa_supplicant/initrd.conf; the image sits unencrypted on the esp, so whoever holds the disk holds
# the wifi key (README, Security)
const WIFI_CONF = "/etc/mkinitcpio-systemd-tool/config/initrd-wifi.conf"

# ssh into the initramfs to answer the passphrase prompt, the console prompt stays the fallback
export def system [cfg: record] {
    if not $cfg.ssh_unlock {
        if not ($HOOK_INSTALL | path exists) { return [] }
        return ($UNITS | append $WIFI_UNIT | each { unit-disable $in } | append (step teardown))
    }
    if (which tinysshd | is-empty) or not ($HOOK_INSTALL | path exists) {
        return []
    }
    [
        (step keys)
        (file-copy mkinitcpio-systemd-tool.conf $"($TOOL_DIR)/mkinitcpio-systemd-tool.conf")
        # the stock file matches eth* only
        (file-copy initrd-network.network $"($TOOL_DIR)/network/initrd-network.network")
        (dropin initrd-tinysshd.service tinysshd.conf)
        # the systemd-tool hook puts enabled units in the image, ConditionPathExists keeps them off the real system
        ...($UNITS | each { unit-enable $in })
        ...(wifi $cfg.wifi)
        (step wire)
    ]
}

# a laptop off its cable joins a home wifi in the initramfs; without the option the image stays wired only
def wifi [enabled: bool]: nothing -> list<record> {
    if not $enabled {
        return [(unit-disable $WIFI_UNIT) (step wifi-teardown)]
    }
    [
        (step wifi-conf)
        (file-copy $WIFI_UNIT $"/etc/systemd/system/($WIFI_UNIT)")
        (unit-enable $WIFI_UNIT)
    ]
}

# one wpa_supplicant network per line of secrets/wifi (ssid, a tab, the passphrase), each key as wpa_passphrase's
# hash; a run without DOTFILES_SECRETS keeps what is there
export def wifi-conf []: nothing -> nothing {
    let wifi = $env.DOTFILES_SECRETS? | default "/nonexistent" | path join wifi
    if not ($wifi | path exists) {
        if not ($WIFI_CONF | path exists) {
            print "note: remote-unlock: secrets/wifi not readable, unlock the secrets and rerun; the initramfs stays wired only"
        }
        return
    }
    let networks = open --raw $wifi | lines | where $it != "" | each {|line|
        let fields = $line | split row "\t"
        if ($fields | length) != 2 { error make {msg: "remote-unlock: secrets/wifi is not one ssid<tab>passphrase per line"} }
        # the passphrase goes in on stdin, never argv; wpa_passphrase's comments repeat it in plain, so they all go
        $fields.1 | ^wpa_passphrase $fields.0 | lines | where not ($it | str trim | str starts-with "#")
    } | flatten
    if not ($WIFI_CONF | path dirname | path exists) { ^install -dm700 ($WIFI_CONF | path dirname) }
    ["ctrl_interface=/run/wpa_supplicant" ...$networks ""] | str join "\n" | save --force $WIFI_CONF
    ^chmod 600 $WIFI_CONF
}

export def wifi-teardown []: nothing -> nothing {
    rm --force $WIFI_CONF $"/etc/systemd/system/($WIFI_UNIT)"
}

# a run without DOTFILES_SECRETS keeps what is there
export def keys []: nothing -> nothing {
    let secrets = $env.DOTFILES_SECRETS? | default "/nonexistent"
    let host = ^uname -n | str trim
    let secret_key = $secrets | path join initramfs-ssh $host sshkeydir .ed25519.sk
    if ($secret_key | path exists) and (ls $secret_key | get 0.size | into int) == $ED25519_SK_BYTES {
        ^install -dm700 $KEYDIR
        ^install -m600 $secret_key $"($KEYDIR)/.ed25519.sk"
        # tinyssh's secret key is the seed then the public key
        open --raw $secret_key | into binary | bytes at 32.. | save --force $"($KEYDIR)/ed25519.pk"
    } else if not ($"($KEYDIR)/.ed25519.sk" | path exists) {
        ^install -dm700 ($KEYDIR | path dirname)
        ^tinysshd-makekey $KEYDIR
        let backup = $"secrets/initramfs-ssh/($host)"
        print ("note: remote-unlock: generated a new initramfs host key; back it up: "
            + $"sudo mkdir -p ($backup) && sudo cp -a ($KEYDIR) ($backup)/sshkeydir")
    }
    let pubkey = $secrets | path join ssh_publickey.asc
    if ($pubkey | path exists) and (open --raw $pubkey | str starts-with "ssh-") {
        ^install -Dm600 $pubkey $AUTHORIZED_KEYS
    } else {
        print ("note: remote-unlock: secrets/ssh_publickey.asc not readable, unlock the secrets and rerun; "
            + "no authorized_keys installed")
    }
}

# after sd-encrypt, so the cryptsetup machinery it feeds is in place
# the hook refuses to build an image without the key file, so no key means no remote unlock yet
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
        let after = if $anchor == "sd-encrypt" { 1 } else { 0 }
        let at = ($hooks | enumerate | where item == $anchor | get 0.index) + $after
        hooks-write (hooks-insert $hooks $HOOK $at)
    }
    cmdline-set rd.neednet=1
}

def unwire []: nothing -> nothing {
    if ($MKINITCPIO | path exists) { hooks-write (hooks-read | where $it != $HOOK) }
    cmdline-unset rd.neednet
}

export def teardown []: nothing -> nothing {
    wifi-teardown
    rm --force --recursive $AUTHORIZED_KEYS /etc/systemd/system/initrd-tinysshd.service.d
    unwire
}
