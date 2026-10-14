#!/usr/bin/env -S nu --no-config-file
# passphrase from the login keyring, else the secrets copy on a fresh install

const REPO = path self | path expand | path dirname | path join .. .. .. | path expand
use ($REPO | path join scripts lib secrets.nu) [secret-is-plaintext]

const PASSPHRASE = "secrets/ssh_passphrase"

def main [...prompt: string]: nothing -> nothing {
    let keyring = do { ^secret-tool lookup ssh-key ssh_privatekey } | complete
    if $keyring.exit_code == 0 { print --no-newline $keyring.stdout; return }
    let file = $REPO | path join $PASSPHRASE
    if not (secret-is-plaintext $file) { exit 1 }
    print (open --raw $file | lines | get --optional 0 | default "")
}
