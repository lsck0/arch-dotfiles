use module.nu *

export const meta = {
    packages: {
        pacman: [age age-plugin-yubikey ccid git-crypt libfido2 openssh pam-u2f pcsclite usbutils yubikey-manager yubikey-personalization]
    }
}

const SECRETS_ISSUE = "/etc/issue.d/dotfiles-secrets.issue"

def secrets-arrived []: nothing -> bool {
    let dir = $env.DOTFILES_SECRETS? | default ""
    $dir != "" and (glob ($dir | path join "**" "*") --no-dir | is-not-empty)
}

export def secrets-issue-clear []: nothing -> nothing { rm --force $SECRETS_ISSUE }

export def system [cfg: record] {
    [
        (file-copy pcsc.rules /etc/polkit-1/rules.d/50-pcsc-wheel.rules)
        (file-copy 70-yubikey-hidraw.rules /etc/udev/rules.d/70-yubikey-hidraw.rules
            --then [sh -c "udevadm control --reload && udevadm trigger --action=change --subsystem-match=hidraw"])
        (unit-enable pcscd.socket --now)
        (if (secrets-arrived) and ($SECRETS_ISSUE | path exists) { step secrets-issue-clear } else { [] })
    ]
}

export def link [cfg: record] {
    let ssh = $nu.home-dir | path join .ssh
    # ssh tries id_ed25519_sk by default, after the agent's keys; a copy, ssh rejects a key file others can read
    let module = $env.DOTFILES | path join configs base yubikey
    let secrets = $env.DOTFILES | path join configs secrets keys yubikey
    let stub = glob ($secrets | path join "ssh-*") | where {|f| not ($f | str ends-with ".pub") } | get --optional 0
    let pub = glob ($module | path join "ssh-*.pub") | get --optional 0
    [
        (if (profile-has secrets) and $stub != null and $pub != null and (secret-is-plaintext $stub) {
            [
                (file-copy $stub ($ssh | path join id_ed25519_sk) --mode 600)
                (file-copy $pub ($ssh | path join id_ed25519_sk.pub))
            ]
        } else { [] })
        (link-commands totp.nu)
    ] | decls-flatten
}
