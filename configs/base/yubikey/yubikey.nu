# `dot secrets unlock|lock|seal` and yubikey enrollment.

use ../../../scripts/lib/profile.nu [profile-load]
use ../../../scripts/lib/secrets.nu [secret-is-plaintext secrets-wanted secrets-keys-chmod]
use ../../../scripts/lib/state.nu [SECRETS_ISSUE]

const REPO = path self ../../..
const KEY_DIR = path self .
const OWNER_DIR = path self ../../secrets/yubikey
const SECRETS = path self ../../secrets
const SEALED_KEY = path self secrets.key.age
const WITNESS = path self ../../secrets/keys/pgp/private.asc
const PAM_ORIGIN = "pam://lsck0"
const SSH_APPLICATION = "ssh:lsck0"
const AGE_SLOT = "1"
const TOUCH_WAIT = 30min
const TOUCH_ATTEMPT_S = "900"
const TOUCH_RETRY = 2sec
# a missed touch times out after seconds; failures this fast in a row are no touch's (offline, no matching identity)
const TOUCH_FAST = 5sec
const TOUCH_FAST_MAX = 3
const INIT_STEPS = [pins pgp ssh u2f age]
const PCSC_REFUSED = "PC/SC not available"
const GITHUB_OVER_SSH = "url.git@github.com:lsck0/.insteadOf=https://github.com/lsck0/"
const SECRETS_PULL = [submodule update --init configs/secrets]

# Clears the install chain's "still locked" login banner once secrets unlock, best effort without a prompt:
# otherwise base/yubikey's system verb clears it on the next system apply.
def secrets-issue-try-clear []: nothing -> nothing {
    if ($SECRETS_ISSUE | path exists) { do { ^sudo -n rm -f $SECRETS_ISSUE } | complete | ignore }
}

def unwanted []: nothing -> bool {
    if (secrets-wanted) { return false }
    print "secrets: this profile has no secrets capability, configs/secrets/ is not pulled or unlocked"
    true
}

def heading [text: string]: nothing -> nothing { print $"\n== ($text)" }

# ykman reads the serial over FIDO HID without pcscd. pcscd refuses a session without a seat (the install chain's
# service, ssh), ykman then warns on stderr and only the PIV applet age unlocks with is out of reach (ccid false).
def card []: nothing -> record<present: bool, serial: string, ccid: bool> {
    let info = if (which ykman | is-empty) { {exit_code: 1} } else { do { ^ykman info } | complete }
    # a Security Key series key shows no serial: nothing to unlock with, so the gpg fallback
    let sn = $info.stdout? | default "" | lines | parse "Serial number: {sn}" | get --optional 0.sn | default "" | str trim
    if $info.exit_code != 0 or $sn == "" { return {present: false, serial: "", ccid: false} }
    {
        present: true
        serial: $sn
        ccid: ($info.stderr | str contains $PCSC_REFUSED | not $in)
    }
}

def recipient [identity: path]: nothing -> string {
    open --raw $identity | lines | parse --regex '^#\s*Recipient: (?<r>.*)$' | get 0.r
}

# --foreground: a background group stops on the tty read; the cap only guards a stalled network.
def with-touch [argv: list<string>]: nothing -> bool {
    let deadline = (date now) + $TOUCH_WAIT
    mut fast = 0
    mut done = false
    while not $done {
        let start = date now
        $done = try { ^timeout --foreground $TOUCH_ATTEMPT_S ...$argv; true } catch { false }
        if $done { break }
        $fast = if ((date now) - $start) < $TOUCH_FAST { $fast + 1 } else { 0 }
        if $fast >= $TOUCH_FAST_MAX or (date now) > $deadline { break }
        print ">>> not done, touch the YubiKey again when it blinks"
        sleep $TOUCH_RETRY
    }
    $done
}

# Decrypt the passphrase-protected ssh stub once before the touch loop, or ssh asks every attempt.
def stub-decrypt [key_file: path]: nothing -> bool {
    let probe = do { ^ssh-keygen -y -P "" -f $key_file } | complete
    if $probe.exit_code == 0 { return true }
    # a stub enrolled by init carries a passphrase; any other failure (the sk/fido provider, a bad read) must not loop
    # on a passphrase prompt
    if not ($probe.stderr | str contains "passphrase") { return false }
    if ($env.DOTFILES_UNATTENDED? | is-not-empty) or not (is-terminal --stdin) { return false }
    print ">>> the YubiKey's ssh stub is passphrase-protected, type its passphrase"
    for _ in 1..3 {
        if (try { ^ssh-keygen -q -p -N "" -f $key_file; true } catch { false }) { return true }
    }
    false
}

def key-file-shred [key: path]: nothing -> nothing {
    if ($key | path exists) { ^shred -u $key }
}

# An empty 600 file for a raw key on the session's tmpfs, which a logout or reboot clears if a run is cut off;
# /tmp where there is no session (root on the ISO).
def key-file-create []: nothing -> path {
    mktemp --tmpdir-path ($env.XDG_RUNTIME_DIR? | default --empty /tmp)
}

def with-key-file [body: closure]: nothing -> nothing {
    let key = key-file-create
    let failed = try { do $body $key; null } catch {|e| $e.msg }
    key-file-shred $key
    if $failed != null { error make {msg: $failed} }
}

# Without a key, git-crypt unlocks with gpg.
def crypt-unlock [key?: path]: nothing -> bool {
    let ok = (do { ^git -C $SECRETS crypt unlock ...([$key] | compact) } | complete).exit_code == 0
    if $ok { secrets-keys-chmod $SECRETS; secrets-issue-try-clear }
    $ok
}

def secrets-pulled []: nothing -> bool {
    $SECRETS | path join .git | path exists
}

def fingerprint []: nothing -> string {
    let profile = profile-load
    if ($profile.gpg_fingerprint | is-empty) { error make {msg: $"yubikey: no gpg_fingerprint in ($profile.file)"} }
    $profile.gpg_fingerprint
}

# Reseals the git-crypt key to every enrolled key's age recipient plus recipients.txt.
export def yubikey-seal []: nothing -> nothing {
    let identities = glob ($KEY_DIR | path join "age-*.identity") | each { [-r (recipient $in)] } | flatten
    let file = $OWNER_DIR | path join recipients.txt
    let listed = ($file | path exists) and (open --raw $file | lines | any { $in !~ '^\s*(#|$)' })
    let recipients = $identities ++ (if $listed { [-R $file] } else { [] })
    if ($recipients | is-empty) {
        error make {msg: $"yubikey: no age identity in ($KEY_DIR) or recipients.txt entry in ($OWNER_DIR) to seal for"}
    }
    with-key-file {|key|
        ^git -C $SECRETS crypt export-key $key
        ^age -e ...$recipients -o $SEALED_KEY $key
    }
}

def card-has-pgp []: nothing -> bool {
    (^ykman openpgp info | str replace --all " " "") | str contains $"Fingerprint:(fingerprint)"
}

def pgp-to-card []: nothing -> nothing {
    let home = mktemp --directory
    "disable-ccid\npcsc-shared\n" | save ($home | path join scdaemon.conf)
    try {
        ^gpg --homedir $home --import ($SECRETS | path join keys pgp/private.asc)
        print "gpg prompt: keytocard -> 1 (signature), key 1, keytocard -> 2 (encryption), save"
        # gpg exits non-zero after a quit without save although keytocard already wrote the card
        do { ^gpg --homedir $home --edit-key (fingerprint) } | complete | ignore
    }
    ^gpgconf --homedir $home --kill all
    rm --recursive --force $home
}

def init-step [step: string, sn: string]: nothing -> nothing {
    match $step {
        pins => {
            if (^ykman fido info | lines | any { $in =~ '^PIN:.*Not set' }) {
                heading "FIDO2 PIN, needed once to create credentials, never for a touch"
                ^ykman fido access change-pin
            }
            heading "OpenPGP PINs: 'Enter PIN' wants the current one, 123456 (admin 12345678) until changed"
            ^ykman openpgp access change-pin
            ^ykman openpgp access change-admin-pin
        }
        pgp => {
            fingerprint | ignore
            heading "the profile's pgp key onto the card"
            if not (card-has-pgp) { pgp-to-card }
            if not (card-has-pgp) { error make {msg: $"yubikey: the card does not hold (fingerprint)"} }
            ^ykman openpgp keys set-touch sig on
            ^ykman openpgp keys set-touch dec on
        }
        ssh => {
            heading "ssh key, touch only; the committed stub gets a passphrase, the git-crypt copy none"
            let stub = $KEY_DIR | path join $"ssh-($sn)"
            let copy = $SECRETS | path join keys yubikey $"ssh-($sn)"
            (^ssh-keygen -t ed25519-sk -O resident -O $"application=($SSH_APPLICATION)" -N ""
                -C $"($env.USER)@yubikey-($sn)" -f $stub)
            # the copy the module installs as ~/.ssh/id_ed25519_sk, before the stub is encrypted
            mkdir ($copy | path dirname)
            ^install -m600 $stub $copy
            while (do { ^ssh-keygen -y -P "" -f $stub } | complete).exit_code == 0 {
                print "the stub is committed, give it a non-empty passphrase"
                ^ssh-keygen -p -f $stub
            }
            ^gh auth refresh -h github.com -s admin:public_key
            ^gh ssh-key add $"($stub).pub" --title $"yubikey-($sn)"
        }
        u2f => {
            heading "pam_u2f for sudo (a touch), reaches /etc/u2f_mappings on the next dot apply"
            let user = $env.USER
            let line = ^pamu2fcfg -o $PAM_ORIGIN -i $PAM_ORIGIN -u $user | str trim
            let file = $OWNER_DIR | path join u2f_keys
            if ($file | path exists) {
                let added = $line | str replace $"($user):" ""
                let lines = open --raw $file | lines | where ($it | str trim) != ""
                if ($lines | is-empty) { $"($line)\n" | save --force $file } else {
                    # the owner's keys sit on line 0 whatever login made them (secrets/yubikey maps them to the owners)
                    $lines | enumerate | each {|l| if $l.index == 0 { $"($l.item):($added)" } else { $l.item } }
                    | to text | save --force $file
                }
            } else {
                $"($line)\n" | save $file
            }
        }
        age => {
            heading "age identity, touch without PIN, for sops and the sealed git-crypt key"
            if not (^ykman piv info | str contains "protected by PIN") {
                print "management key: press enter for the default, then give the PIV PIN"
                ^ykman piv access change-management-key -a TDES --protect
            }
            (^age-plugin-yubikey --generate --serial $sn --slot $AGE_SLOT --name lsck0 --pin-policy never
                --touch-policy always) | save --force ($KEY_DIR | path join $"age-($sn).identity")
            yubikey-seal
        }
        _ => { error make {msg: $"yubikey: unknown init step ($step), one of ($INIT_STEPS | str join ' ')"} }
    }
}

# Enrolls the plugged-in key, the given steps or all of pins, pgp, ssh, u2f and age.
export def yubikey-init [...steps: string]: nothing -> nothing {
    let card = card
    if not $card.present { error make {msg: "yubikey: no YubiKey detected"} }
    if not $card.ccid { error make {msg: "yubikey: pcscd refuses this session, enroll from a local login"} }
    if not (secret-is-plaintext $WITNESS) { error make {msg: "yubikey: secrets are locked, unlock them first"} }
    let sn = $card.serial
    for step in (if ($steps | is-empty) { $INIT_STEPS } else { $steps }) { init-step $step $sn }
    let identity = $KEY_DIR | path join $"age-($sn).identity"
    let r = if ($identity | path exists) { recipient $identity } else { "" }
    heading $"done: commit configs/base/yubikey; homelab .sops.yaml needs ($r)"
}

# Without a YubiKey (WSL): gh credentials, else the account's ssh key; never an https prompt.
def secrets-pull-with-account []: nothing -> nothing {
    let pull = {|config: list<string>|
        (do { with-env {GIT_TERMINAL_PROMPT: "0"} { ^git -C $REPO ...$config ...$SECRETS_PULL } }
            | complete).exit_code == 0
    }
    let gh = (which gh | is-not-empty) and ((do { ^gh auth status } | complete).exit_code == 0)
    if $gh and (do $pull [-c "credential.helper=" -c "credential.helper=!gh auth git-credential"]) { return }
    let ssh = "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
    if not (do $pull [-c $"core.sshCommand=($ssh)" -c $GITHUB_OVER_SSH]) {
        error make {msg: "yubikey: cannot fetch the private secrets submodule: log in with `gh auth login`, or add an ssh key with access to github.com/lsck0/secrets, then rerun"}
    }
}

def unlock-identity [identity: path]: nothing -> nothing {
    if not ($identity | path exists) { error make {msg: $"yubikey: no identity file '($identity)'"} }
    if not ($SEALED_KEY | path exists) { error make {msg: $"yubikey: no sealed key ($SEALED_KEY)"} }
    if not (secrets-pulled) { secrets-pull-with-account }
    if (secret-is-plaintext $WITNESS) {
        print "yubikey: secrets already unlocked"
        return
    }
    with-key-file {|key|
        if (do { ^age -d -i $identity -o $key $SEALED_KEY } | complete).exit_code != 0 {
            error make {msg: $"yubikey: ($identity) does not open ($SEALED_KEY)"}
        }
        if not (crypt-unlock $key) { error make {msg: "yubikey: git-crypt unlock failed"} }
    }
}

# Unlocks configs/secrets/ with a yubikey touch (gpg when no key is present), or with the age identity --identity.
export def yubikey-unlock [--identity: path]: nothing -> nothing {
    if (unwanted) { return }
    if $identity != null { return (unlock-identity $identity) }
    let pulled = secrets-pulled
    # every dot apply comes through here: unlocked, there is nothing to ask the key
    if $pulled and (secret-is-plaintext $WITNESS) { return }
    let card = card
    if not $card.present {
        if (which lsusb | is-not-empty) and (do { ^lsusb -d 1050: } | complete).exit_code == 0 {
            print "yubikey: plugged in but ykman can not reach it, check pcscd and its polkit rule"
        }
        if $pulled and not (secret-is-plaintext $WITNESS) {
            if not (crypt-unlock) { print "yubikey: no key present and pgp git-crypt unlock failed" }
        } else {
            print "yubikey: none plugged in, secrets stay as they are"
        }
        return
    }
    let sn = $card.serial
    let stub = $KEY_DIR | path join $"ssh-($sn)"
    let identity = $KEY_DIR | path join $"age-($sn).identity"
    if not ([$stub $identity $SEALED_KEY] | all { path exists }) {
        print $"yubikey: ($sn) is not enrolled \(dot secrets init\), skipping"
        return
    }
    # a dot apply without a terminal (an agent's, the settings panel's): nobody sees the touch cue, and the wait would
    # hold the run for TOUCH_WAIT
    if ($env.DOTFILES_UNATTENDED? | is-not-empty) {
        print "yubikey: no terminal for the touch cue, secrets stay locked: dot secrets unlock"
        return
    }
    if not $pulled {
        let key_file = key-file-create
        ^install -m600 $stub $key_file
        if not (stub-decrypt $key_file) {
            key-file-shred $key_file
            print "yubikey: the ssh stub stays locked without its passphrase, secrets are not pulled"
            return
        }
        print ">>> touch the YubiKey to pull the secrets (the clone takes a while after the touch)"
        let ssh = $"ssh -i ($key_file) -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
        let ok = with-touch [git -C $REPO -c $"core.sshCommand=($ssh)" -c $GITHUB_OVER_SSH ...$SECRETS_PULL]
        key-file-shred $key_file
        if not $ok { print "yubikey: pull failed or no touch" }
        if not (secrets-pulled) { return }
    }
    if (secret-is-plaintext $WITNESS) { return }
    if not $card.ccid {
        print "yubikey: pcscd refuses this session, secrets stay locked; unlock from a local login: dot secrets unlock"
        return
    }
    print ">>> touch the YubiKey to unlock the secrets"
    with-key-file {|key|
        if not (with-touch [age -d -i $identity -o $key $SEALED_KEY]) {
            print "yubikey: unlock failed or no touch"
        } else if not (crypt-unlock $key) {
            print "yubikey: git-crypt unlock failed"
        }
    }
}

export def yubikey-lock []: nothing -> nothing {
    if (unwanted) { return }
    ^git -C $SECRETS crypt lock
}
