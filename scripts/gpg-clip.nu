#!/usr/bin/env -S nu --no-config-file

const PICKER = path self | path expand | path dirname | path join picker.nu
const APP = "gpg-clip"
const FORGET_TIMEOUT_S = "3"
const DONE = "DONE"

def --wrapped notify [...args: string]: nothing -> nothing { ^notify-send $"--app-name=($APP)" ...$args }

def clip-get []: nothing -> string {
    let clip = do { ^wl-paste --no-newline } | complete
    if $clip.exit_code != 0 or $clip.stdout == "" {
        notify "Clipboard is empty"
        exit 1
    }
    $clip.stdout | str trim --right --char "\n"
}

# hashed from the clipboard as the history holds it, trailing newlines included
def clip-hash []: nothing -> string { ^wl-paste --type text --no-newline | hash md5 }

def clip-put [text: string, hash: string]: nothing -> nothing {
    $"($text)\n" | ^wl-copy
    let shell = $nu.home-dir | path join .config quickshell
    do { ^timeout $FORGET_TIMEOUT_S quickshell ipc -p $shell call clipboard forget $hash } | complete | ignore
}

# the status lines, not GOODSIG alone: good means a valid signature by a fully or ultimately trusted key
def sig-report [status: list<string>]: nothing -> bool {
    let has = {|pattern| $status | any { $in =~ $'^\[GNUPG:\] ($pattern)' } }
    let signer = $status | parse --regex '^\[GNUPG:\] (?:GOOD|EXP|EXPKEY|REVKEY|BAD)SIG [0-9A-F]* (?<who>.*)$'
        | get --optional 0.who | default ""
    # the primary key's fingerprint when gpg gives it, else the signing subkey's; ERRSIG has only the key id
    let fpr = $status | each { split row --regex '\s+' } | where { $in.1? in [VALIDSIG ERRSIG] } | get --optional 0
        | if $in == null { "" } else if $in.1 == ERRSIG or ($in.11? | default "") == "" { $in.2 } else { $in.11 }
    if (do $has BADSIG) {
        notify --urgency=critical "BAD signature" $"The message was altered or the signature is forged\n($signer)"
    } else if (do $has ERRSIG) {
        notify --urgency=critical "Unverified signature" $"Missing key or unsupported algorithm\nkey ($fpr)"
    } else if (do $has REVKEYSIG) {
        notify --urgency=critical "Signature by a revoked key" $"($signer)\n($fpr)"
    } else if (do $has '(EXPKEYSIG|EXPSIG)') {
        notify --urgency=critical "Expired signature or key" $"($signer)\n($fpr)"
    } else if (do $has GOODSIG) {
        if (do $has VALIDSIG) and (do $has 'TRUST_(FULLY|ULTIMATE)') {
            notify "Good signature" $"($signer)\n($fpr)"
        } else {
            let body = $"Not certified, the name may be anyone's\n($signer)\n($fpr)"
            notify --urgency=critical "Signature by an untrusted key" $body
        }
    } else {
        return false
    }
    true
}

def key-list [capability: string, --secret]: nothing -> list<string> {
    let listing = if $secret { "--list-secret-keys" } else { "--list-keys" }
    do { ^gpg $listing --with-colons } | complete | get stdout | lines
    | split list --regex --split before '^(pub|sec):' | where { ($in.0? | default "") =~ '^(pub|sec):' }
    | each {|key|
        let rows = $key | each { split row ":" }
        let uid = $rows | where { $in.0 == uid and $in.1 != r } | get --optional 0.9
        let usable = ($rows.0.11 | str contains $capability) and $rows.0.1 not-in [r e]
        if $usable and $uid != null { $"($uid)  ($rows | where { $in.0 == fpr } | first | get 9)" }
    }
    | compact | sort | uniq
}

def pick [prompt: string, keys: list<string>]: nothing -> string {
    $keys | str join "\n" | do { ^$PICKER -p $prompt } | complete | get stdout | str trim
    | split row --regex '\s+' | last
}

def uid-of [fpr: string]: nothing -> string {
    ^gpg --list-keys --with-colons $fpr | lines | where { $in starts-with "uid:" } | first | split row ":" | get 9
}

# gpg.conf's default-key comes first, so enter signs with it; the only secret key signs without asking
def signer-pick []: nothing -> string {
    let keys = key-list S --secret
    if ($keys | is-empty) {
        notify --urgency=critical "No secret key to sign with"
        exit 1
    }
    if ($keys | length) == 1 { return ($keys.0 | split row --regex '\s+' | last) }
    let default = ^gpgconf --list-options gpg | lines | each { split row ":" } | where { $in.0 == default-key }
        | get --optional 0.9 | default "" | str replace --all '"' ""
    let first = if $default == "" { [] } else { $keys | where { str contains $default } }
    pick "sign as" ($first ++ ($keys | where $it not-in $first))
}

# bemenu picks one line, so recipients are picked one at a time until done
def recipients-pick []: nothing -> list<string> {
    let keys = key-list E
    mut chosen = []
    loop {
        let picked = $chosen
        let done = if ($picked | is-empty) { [] } else { [$"done  \(($picked | length) picked\)  ($DONE)"] }
        let fpr = pick "encrypt to" ($done ++ ($keys | where {|k| not ($picked | any {|f| $k | str contains $f }) }))
        if $fpr in ["" $DONE] { break }
        $chosen = $chosen | append $fpr
    }
    $chosen
}

# Decrypt, verify, encrypt or clear-sign the clipboard; plaintext is shown, never copied.
def main []: nothing -> nothing {
    print --stderr $"usage: ($APP) decrypt|encrypt|sign"
    exit 2
}

# Decrypt or verify the clipboard and show the plaintext in a pager.
def "main decrypt" []: nothing -> nothing {
    let text = clip-get
    let runtime = $env.XDG_RUNTIME_DIR? | default "/tmp"
    let out = mktemp --tmpdir-path $runtime $"($APP).XXXXXX"
    let status = $"($text)\n" | do { ^gpg --batch --yes --status-fd 1 --decrypt --output $out } | complete
        | get stdout | lines
    if not (sig-report $status) and not ($status | any { $in =~ '^\[GNUPG:\] (DECRYPTION_OKAY|PLAINTEXT)' }) {
        rm --force $out
        notify --urgency=critical "Nothing to decrypt or verify" "No OpenPGP message on the clipboard"
        exit 1
    }
    if (ls $out | first | get size) == 0B {
        rm --force $out
        return
    }
    # the viewer unlinks it as soon as it holds it open
    try {
        ^ghostty $"--title=($APP)" -e sh -c 'exec 3<"$1"; rm -f -- "$1"; less /dev/fd/3' _ $out
    } catch { rm --force $out }
}

# Encrypt the clipboard to picked recipients, signed, and copy the armored message.
def "main encrypt" []: nothing -> nothing {
    let text = clip-get
    let hash = clip-hash
    let recipients = recipients-pick
    if ($recipients | is-empty) { return }
    let signer = signer-pick
    if $signer == "" { return }
    # the signer is a recipient too, so the sent message stays readable here
    let to = $recipients | append $signer | each { [--recipient $in] } | flatten
    let armored = $"($text)\n" | do { ^gpg --armor --local-user $signer --sign --encrypt ...$to } | complete
    if $armored.exit_code != 0 {
        notify --urgency=critical "Encryption failed"
        exit 1
    }
    clip-put ($armored.stdout | str trim --right --char "\n") $hash
    notify $"Encrypted and signed as (uid-of $signer)" $"For ($recipients | each { uid-of $in } | str join ', ')"
}

# Clear-sign the clipboard and copy the signed text.
def "main sign" []: nothing -> nothing {
    let text = clip-get
    let hash = clip-hash
    let signer = signer-pick
    if $signer == "" { return }
    let signed = $"($text)\n" | do { ^gpg --local-user $signer --clearsign } | complete
    if $signed.exit_code != 0 {
        notify --urgency=critical "Signing failed"
        exit 1
    }
    clip-put ($signed.stdout | str trim --right --char "\n") $hash
    notify $"Signed as (uid-of $signer)" "Clear-signed text copied"
}
