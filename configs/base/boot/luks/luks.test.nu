#!/usr/bin/env -S nu --no-config-file
# The root's rd.luks.options and the enrol notes from cryptsetup's own luksDump of a LUKS2 image file (no root, no
# device): a token is asked for only when enrolled, the passphrase always stays (tries=0), and a TPM2 seal is only ever
# suggested with a pin, a pinless one flagged.

use std/assert
use mod.nu [luks-unlisted unlock-plan]

const PART = "nvme0n1p2"
const BASE = "tpm2-measure-pcr=yes,tries=0"
const TPM2 = '{"type":"systemd-tpm2","keyslots":["0"],"tpm2-blob":"AAAA","tpm2-pcrs":[7,15],"tpm2-pcr-bank":"sha256","tpm2-primary-alg":"ecc","tpm2-policy-hash":"00","tpm2-pin":@PIN@}'
const FIDO2 = '{"type":"systemd-fido2","keyslots":["0"],"fido2-credential":"AAAA","fido2-salt":"AAAA","fido2-rp":"io.systemd.cryptsetup","fido2-clientPin-required":false,"fido2-up-required":true,"fido2-uv-required":false}'
const NOTE_FIDO = "no yubikey enrolled"
const NOTE_TPM2 = "no TPM2 seal enrolled"
const NOTE_PINLESS = "TPM2 seal without a pin"
const NOTE_HEADER = "back up the header"

# The image's tokens, exactly these, as root-unlock reads them from the json metadata.
def dump [image: path, tokens: list<string>]: nothing -> list<record> {
    for id in (^cryptsetup luksDump --dump-json-metadata $image | from json | get tokens | columns) {
        ^cryptsetup token remove --token-id $id $image | complete | ignore
    }
    for t in $tokens { $t | ^cryptsetup token import $image | complete | ignore }
    ^cryptsetup luksDump --dump-json-metadata $image | from json | get tokens | values
}

def main [] {
    crypttab-check
    if (which cryptsetup | is-empty) { print --stderr "luks.test: skipped: needs cryptsetup"; return }
    let dir = mktemp --directory --tmpdir dot-luks-test-XXXXXX
    let image = $dir | path join root.img
    ^truncate -s 20M $image
    "pw" | ^cryptsetup luksFormat --batch-mode --type luks2 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file - $image | complete | ignore
    let pin = $TPM2 | str replace "@PIN@" "true"
    let pinless = $TPM2 | str replace "@PIN@" "false"
    let cases = [
        [what tokens changed options notes];
        ["no token" [] true $BASE [$NOTE_FIDO $NOTE_TPM2 $NOTE_HEADER]]
        ["no token, header seen" [] false $BASE [$NOTE_FIDO]]
        ["tpm2 with pin" [$pin] true $"tpm2-device=auto,($BASE)" [$NOTE_FIDO $NOTE_HEADER]]
        ["tpm2 without pin" [$pinless] false $"tpm2-device=auto,($BASE)" [$NOTE_FIDO $NOTE_PINLESS]]
        ["fido2" [$FIDO2] true $"fido2-device=auto,($BASE)" [$NOTE_TPM2 $NOTE_HEADER]]
        ["fido2, header seen" [$FIDO2] false $"fido2-device=auto,($BASE)" []]
        ["tpm2 with pin, then fido2" [$pin $FIDO2] false $"tpm2-device=auto,fido2-device=auto,($BASE)" []]
        # systemd-cryptenroll's usual order: the key enrolled first, the seal after
        ["tpm2 with pin after fido2" [$FIDO2 $pin] false $"tpm2-device=auto,fido2-device=auto,($BASE)" []]
        ["tpm2 without pin after fido2" [$FIDO2 $pinless] false $"tpm2-device=auto,fido2-device=auto,($BASE)" [$NOTE_PINLESS]]
    ]
    let failed = $cases | each {|c| case-check $image $c } | flatten
    rm --recursive --force $dir
    assert ($failed | is-empty) ($failed | str join "\n")
}

# What one case got wrong, empty when it holds.
def case-check [image: path, c: record]: nothing -> list<string> {
    let plan = unlock-plan (dump $image $c.tokens) $PART $c.changed
    let kinds = $plan.notes | each {|n| [$NOTE_FIDO $NOTE_TPM2 $NOTE_PINLESS $NOTE_HEADER] | where {|k| $n | str contains $k } | first }
    let pinless_enrol = $plan.notes | where ($it | str contains "systemd-cryptenroll --tpm2") | where not ($it | str contains "--tpm2-with-pin=yes")
    [
        (if $plan.cmdline != $"rd.luks.options=($c.options)" { $"($c.what): ($plan.cmdline), wants rd.luks.options=($c.options)" })
        (if $kinds != $c.notes { $"($c.what): notes ($kinds | to nuon), wants ($c.notes | to nuon)" })
        (if ($pinless_enrol | is-not-empty) { $"($c.what): a TPM2 enrol without a pin: ($pinless_enrol | to nuon)" })
    ] | compact
}

# A partition a kept crypttab line already opens, by its luks-<uuid> name or by its device under any name, gets no
# second entry.
def crypttab-check []: nothing -> nothing {
    let parts = [[name uuid]; [sda1 u1] [sda2 u2] [sda3 u3] [sda4 u4] [sda5 u5]]
    let kept = [
        "# comment UUID=u5"
        ""
        "luks-u1\tUUID=nope\tnone\tluks"
        "data UUID=u2 /etc/cryptsetup-keys.d/data.key luks"
        "  scratch\t/dev/disk/by-uuid/u3  none luks"
        "swap /dev/sda4 /dev/urandom swap"
    ]
    let got = luks-unlisted $kept $parts | get name
    assert equal $got [sda5] $"crypttab: unlisted ($got | to nuon), wants [sda5]"
}
