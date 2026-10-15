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

# ssh into the initramfs to answer the passphrase prompt, the console prompt stays the fallback
export def system [cfg: record] {
    if not $cfg.ssh_unlock {
        if not ($HOOK_INSTALL | path exists) { return [] }
        return ($UNITS | each { unit-disable $in } | append (step teardown))
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
        (step wire)
    ]
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
    rm --force --recursive $AUTHORIZED_KEYS /etc/systemd/system/initrd-tinysshd.service.d
    unwire
}
