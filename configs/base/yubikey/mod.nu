use module.nu *

# install: its verb runs again right after the install pass brought its packages, before config
export const meta = {
    phase: install
    packages: {
        pacman: [age age-plugin-yubikey ccid git-crypt libfido2 openssh pam-u2f pcsclite usbutils yubikey-manager yubikey-personalization]
    }
}

def secrets-arrived []: nothing -> bool { glob (system-secret "**" "*") --no-dir | is-not-empty }

export def secrets-issue-clear []: nothing -> nothing { rm --force $SECRETS_ISSUE }

export def system [cfg: record] {
    [
        (polkit-rules pcsc.rules --name 50-pcsc-wheel.rules)
        (udev-rules 70-yubikey-hidraw.rules --action=change --subsystem-match=hidraw)
        (unit-enable pcscd.socket --now)
        (if (secrets-arrived) and ($SECRETS_ISSUE | path exists) { step secrets-issue-clear })
    ]
}

export def link [cfg: record] {
    let ssh = $nu.home-dir | path join .ssh
    # ssh tries id_ed25519_sk by default, after the agent's keys; a copy, ssh rejects a key file others can read
    let secrets = secret-path keys yubikey
    # a stub and its public key by serial (glob's order is the directory's); the lowest enrolled serial is the default
    let key = glob ($secrets | path join "ssh-*") | where {|f| not ($f | str ends-with ".pub") } | sort
        | each {|stub| {stub: $stub, pub: ($"($stub | path basename).pub" | path expand)} }
        | where { $in.pub | path exists } | get --optional 0
    [
        (if (profile-has secrets) and $key != null and (secret-is-plaintext $key.stub) {
            [
                (file-copy $key.stub ($ssh | path join id_ed25519_sk) --mode 600)
                (file-copy $key.pub ($ssh | path join id_ed25519_sk.pub))
            ]
        })
        (link-commands totp.nu)
    ]
}
