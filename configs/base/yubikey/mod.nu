use module.nu *

export const meta = {
    packages: {
        pacman: [age age-plugin-yubikey ccid git-crypt libfido2 pcsclite yubikey-manager yubikey-personalization]
    }
}

export def system [cfg: record] {
    [
        (file-copy pcsc.rules /etc/polkit-1/rules.d/50-pcsc-wheel.rules)
        (file-copy 70-yubikey-hidraw.rules /etc/udev/rules.d/70-yubikey-hidraw.rules
            --then [sh -c "udevadm control --reload && udevadm trigger --action=change --subsystem-match=hidraw"])
        (unit-enable pcscd.socket --now)
    ]
}

export def link [cfg: record] {
    let ssh = $nu.home-dir | path join .ssh
    # ssh tries id_ed25519_sk by default, after the agent's keys; a copy, ssh rejects a key file others can read
    let stub = glob ssh-* | where not ($it | str ends-with .pub) | get --optional 0
    [
        (if (profile-has identity) and $stub != null {
            [
                (file-copy $stub ($ssh | path join id_ed25519_sk) --mode 600)
                (file-copy $"($stub).pub" ($ssh | path join id_ed25519_sk.pub))
            ]
        } else { [] })
        (link-commands totp.nu)
    ] | decls-flatten
}
