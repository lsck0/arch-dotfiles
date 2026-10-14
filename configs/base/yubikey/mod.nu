use module.nu *

export const meta = {
    packages: {
        pacman: [age age-plugin-yubikey ccid git-crypt libfido2 pcsclite yubikey-manager yubikey-personalization]
    }
}

# card and fido access for every admin, whether or not anyone enrolled a key yet
export def system [cfg: record] {
    [
        (file-copy pcsc.rules /etc/polkit-1/rules.d/50-pcsc-wheel.rules)
        # a replug applies it otherwise
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
        (if (profile-has secrets) { step sops-keys } else { [] })
        (link-commands totp.nu)
    ] | decls-flatten
}

# sops identities, merged so hand-added age keys stay; a step, so the secret key never travels in a declaration
export def sops-keys []: nothing -> nothing {
    let file = $nu.home-dir | path join .config sops age keys.txt
    let age = $env.DOTFILES | path join secrets age.txt
    let unlocked = (secret-is-plaintext $age) and (open --raw $age | lines | any { str starts-with AGE-SECRET-KEY- })
    let enrolled = glob age-*.identity | each { open --raw $in | lines } | flatten
    let want = (if $unlocked { open --raw $age | lines } else { [] }) ++ $enrolled
    let have = if ($file | path exists) { open --raw $file | lines } else { [] }
    let missing = $want | where $it not-in $have
    if ($missing | is-empty) { return }
    mkdir ($file | path dirname)
    $have ++ $missing | str join "\n" | $"($in)\n" | save --force $file
    ^chmod 600 $file
}
