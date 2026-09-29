# YubiKey

Enrollment runbook. Inert until a key is enrolled: PAM falls through to the
password and SSH stays on the plain ssh-agent.

Already set up by install.sh: `yubikey-manager`, `pam-u2f`, `libfido2`,
`pcsclite`, `ccid`, `yubikey-personalization`, `pcscd.socket`, an empty
`~/.config/Yubico/u2f_keys`, and `~/.gnupg/gpg-agent.conf` with ssh support.

Enroll a second key (or keep a password/SSH path) before relying on the first.
Every PAM line is `sufficient nouserok`; never change one to `required`.

## 1. OpenPGP on the card

Key `73CFB23B7E67BF7E` (git-crypt, pass) has no `[A]` subkey yet; SSH needs one.
Default PINs: user `123456`, admin `12345678`.

    gpg --card-edit
    gpg/card> admin
    gpg/card> passwd        # change user (1) and admin (3) PINs
    gpg/card> quit

    gpg --expert --edit-key 73CFB23B7E67BF7E
    gpg> addkey              # capability: Authenticate only
    gpg> key 1               # select a subkey
    gpg> keytocard           # repeat per subkey (sign/encrypt/auth)
    gpg> save

Or generate on-card (back up first):

    gpg --card-edit
    gpg/card> admin
    gpg/card> generate

    gpg --card-status

## 2. FIDO2 for PAM

    pamu2fcfg >> ~/.config/Yubico/u2f_keys      # primary key
    pamu2fcfg -n >> ~/.config/Yubico/u2f_keys   # backup key
    sudo -k && sudo true                        # test in a new shell

sudo and login read `/home/luca/.config/Yubico/u2f_keys` as root. To use
`/etc/u2f_mappings` instead, change `authfile=` in configs/pam (quickshell-lock
and the line inserted by link.sh).

## 3. SSH via gpg-agent

    gpg --export-ssh-key 73CFB23B7E67BF7E

In configs/uwsm/env set:

    export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/gnupg/S.gpg-agent.ssh"

Then:

    systemctl --user disable --now ssh-add.service ssh-agent.service
    export GPG_TTY=$(tty)
    gpg-connect-agent updatestartuptty /bye

Log out and back in; `ssh-add -L` should list the card key. To revert, restore
the ssh-agent socket line and re-enable ssh-agent.service.

## 4. OTP slots

Short touch = slot 1 (static password), long touch = slot 2 (challenge-response).

    ykman otp static --generate 1
    ykman otp static 1 'my-master-password'
    ykman otp chalresp --generate 2
    ykman otp chalresp --touch 2 <hexkey>
    ykman otp info
    ykman otp chalresp 2 <challenge>

## 5. pcscd and scdaemon

If ykman reports the card busy, release it from gpg:

    gpgconf --kill scdaemon

Do not add `disable-ccid` to scdaemon.conf.
