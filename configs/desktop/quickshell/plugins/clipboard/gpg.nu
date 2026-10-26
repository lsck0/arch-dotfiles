#!/usr/bin/env -S nu --no-config-file --stdin
# Clipboard OpenPGP: entry on stdin, one JSON object out; plaintext never in argv, a file or the clipboard.

def emit [record: record]: nothing -> nothing { print ($record | to json --raw) }

def status-of [stderr: string]: nothing -> list<string> {
    $stderr | lines | where { $in starts-with "[GNUPG:] " }
}

# good, untrusted, bad, expired, revoked, unverified or none.
def signature [status: list<string>]: nothing -> record {
    let has = {|pattern| $status | any { $in =~ $'^\[GNUPG:\] ($pattern)' } }
    let signer = $status | parse --regex '^\[GNUPG:\] (?:GOOD|EXP|EXPKEY|REVKEY|BAD)SIG [0-9A-F]* (?<who>.*)$'
        | get --optional 0.who | default ""
    let fpr = $status | each { split row --regex '\s+' } | where { $in.1? in [VALIDSIG ERRSIG] } | get --optional 0
        | if $in == null { "" } else if $in.1 == ERRSIG or ($in.11? | default "") == "" { $in.2 } else { $in.11 }
    let state = if (do $has BADSIG) { "bad" } else if (do $has ERRSIG) { "unverified" } else if (do $has REVKEYSIG) {
        "revoked"
    } else if (do $has '(EXPKEYSIG|EXPSIG)') { "expired" } else if (do $has GOODSIG) {
        if (do $has VALIDSIG) and (do $has 'TRUST_(FULLY|ULTIMATE)') { "good" } else { "untrusted" }
    } else { "none" }
    {state: $state, signer: $signer, fpr: $fpr}
}

def keys-of [listing: string]: nothing -> list<record> {
    do { ^gpg $listing --with-colons } | complete | get stdout | lines
    | split list --regex --split before '^(pub|sec):' | where { ($in.0? | default "") =~ '^(pub|sec):' }
    | each {|key|
        let rows = $key | each { split row ":" }
        let uid = $rows | where { $in.0 == uid and $in.1 != r } | get --optional 0.9
        let fpr = $rows | where { $in.0 == fpr } | get --optional 0.9
        let validity = $rows.0.1
        if $uid != null and $fpr != null and $validity not-in [r e] { {fpr: $fpr, uid: $uid, caps: $rows.0.11, validity: $validity} }
    }
    | compact
}

def default-key []: nothing -> string {
    do { ^gpgconf --list-options gpg } | complete | get stdout | lines | each { split row ":" }
    | where { $in.0 == default-key } | get --optional 0.9 | default "" | str replace --all '"' ""
}

# The key that signs: gpg's default-key when it is a secret signing key, else the first one.
def signer []: nothing -> any {
    let secret = keys-of "--list-secret-keys" | where { $in.caps =~ S }
    let default = default-key
    $secret | where {|k| $default != "" and ($k.fpr | str ends-with ($default | str uppercase)) } | append $secret
    | get --optional 0.fpr
}

def main []: nothing -> nothing {
    print --stderr "usage: gpg.nu keys|encrypt <fpr>...|decrypt, the entry on stdin"
    exit 2
}

# Own keys first; valid = certified, which gpg --batch encrypts to without a trust override.
def "main keys" []: nothing -> nothing {
    let own = keys-of "--list-secret-keys" | get fpr
    let keys = keys-of "--list-keys" | where { $in.caps =~ E }
        | each {|k| {fpr: $k.fpr, uid: $k.uid, own: ($k.fpr in $own), valid: ($k.validity in [f u])} }
        | sort-by --reverse own | uniq-by fpr
    emit {keys: $keys, signer: (signer)}
}

# --trust-unverified: the user confirmed an uncertified recipient in the window.
def "main encrypt" [...recipients: string, --trust-unverified]: string -> nothing {
    let text = $in
    let me = signer
    if $me == null { return (emit {ok: false, error: "no secret key to sign with"}) }
    if ($recipients | is-empty) { return (emit {ok: false, error: "no recipient picked"}) }
    let to = $recipients | append $me | uniq | each { [--recipient $in] } | flatten
    let trust = if $trust_unverified { [--trust-model always] } else { [] }
    let run = $"($text)\n" | do { ^gpg --batch ...$trust --armor --local-user $me --sign --encrypt ...$to } | complete
    if $run.exit_code != 0 { return (emit {ok: false, error: ($run.stderr | lines | where { not ($in starts-with "[GNUPG:]") } | last | default "gpg failed")}) }
    emit {ok: true, armored: ($run.stdout | str trim --right --char "\n")}
}

# Plaintext only with DECRYPTION_OKAY and no failure line: gpg streams a tampered message first.
def "main decrypt" []: string -> nothing {
    let run = $in | do { ^gpg --batch --status-fd 2 --decrypt } | complete
    let status = status-of $run.stderr
    let has = {|pattern| $status | any { $in =~ $'^\[GNUPG:\] ($pattern)' } }
    let sig = signature $status
    if (do $has 'BEGIN_DECRYPTION') {
        if (do $has '(DECRYPTION_FAILED|BADMDC)') or not (do $has 'DECRYPTION_OKAY') {
            return (emit {ok: false, error: "decryption failed: no key for it, or the message was altered or cut short"})
        }
    } else if $sig.state == "none" {
        return (emit {ok: false, error: "no OpenPGP message in this entry"})
    }
    if $run.exit_code != 0 and $sig.state in [none good untrusted] {
        return (emit {ok: false, error: ($run.stderr | lines | where { not ($in starts-with "[GNUPG:]") } | last | default "gpg failed")})
    }
    emit {ok: true, plaintext: $run.stdout, signature: $sig}
}
