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

# its packages are the platform's extra_packages: a module always present would put them on every machine
export const meta = {volatile: true}

const HOOK = "systemd-tool"
const TOOL_DIR = "/etc/mkinitcpio-systemd-tool"
# initrd-shell.service's InitrdPath source for the initramfs /root/.ssh/authorized_keys; never a key on the real root
const AUTHORIZED_KEYS = "/etc/mkinitcpio-systemd-tool/config/authorized_keys"
const KEYDIR = "/etc/tinyssh/sshkeydir"
const UNITS = [initrd-network.service initrd-tinysshd.service]
const HOOK_INSTALL = "/usr/lib/initcpio/install/systemd-tool"
const ED25519_SK_BYTES = 64

# a tinyssh server in the systemd initramfs: wake the box, ssh into early boot, answer the passphrase prompt. the
# console prompt stays the local fallback, so a broken setup never bricks boot. README.md has the first-boot drill
export def system [cfg: record] {
    if not $cfg.ssh_unlock {
        # dropping the option removes the wiring, so a reused machine stops exposing an initramfs ssh
        if not ($HOOK_INSTALL | path exists) { return [] }
        return ($UNITS | each { unit-disable $in } | append (step teardown))
    }
    if (which tinysshd | is-empty) or not ($HOOK_INSTALL | path exists) {
        # mkinitcpio-systemd-tool, tinyssh, tinyssh-convert and busybox are the platform's extra_packages
        return []
    }
    [
        (step keys)
        # use the dedicated host key above, never reconvert the system's /etc/ssh one at build time
        (file-copy mkinitcpio-systemd-tool.conf $"($TOOL_DIR)/mkinitcpio-systemd-tool.conf")
        # the wired nic by wildcard over dhcp, whose reservation keeps the address; the stock file matches eth* only
        (file-copy initrd-network.network $"($TOOL_DIR)/network/initrd-network.network")
        (dropin initrd-tinysshd.service tinysshd.conf)
        # ConditionPathExists=/etc/initrd-release keeps them off the running system; the enable links are what the
        # systemd-tool install hook scans to put them in the image
        ...($UNITS | each { unit-enable $in })
        (step wire)
    ]
}

# both arrive as data in DOTFILES_SECRETS (scripts/lib/system.nu SYSTEM_SECRETS); a run without them keeps what is there
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

# after sd-encrypt, so the cryptsetup machinery it feeds is in place; rd.neednet brings the nic up before the prompt
export def wire []: nothing -> nothing {
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

export def teardown []: nothing -> nothing {
    rm --force --recursive $AUTHORIZED_KEYS /etc/systemd/system/initrd-tinysshd.service.d
    if ($MKINITCPIO | path exists) { hooks-write (hooks-read | where $it != $HOOK) }
    cmdline-unset rd.neednet
}
