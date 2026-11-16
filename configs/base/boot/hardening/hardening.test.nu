#!/usr/bin/env -S nu --no-config-file
# The KSPP cmdline: the install writes a subset of what boot/hardening keeps (so the first apply only adds), and
# relax_mitigations replaces a hardening token by its key instead of setting both.

use mod.nu [system harden-tokens]
use ../boot.nu [key-of]

const BOOTSTRAP = path self ../../../../scripts/lib/bootstrap.nu
# the install's own tokens that are no hardening: boot mode and two power or memory choices
const INSTALL_ONLY = [rw zswap.enabled nmi_watchdog]

def fail [msg: string] { error make {msg: $"hardening.test: ($msg)"} }

def keys-unique [tokens: list<string>]: nothing -> bool {
    ($tokens | each { key-of $in } | uniq | length) == ($tokens | length)
}

def main [] {
    let tail = open --raw $BOOTSTRAP | parse --regex '(?m)^const CMDLINE_TAIL = "(?<t>[^"]*)"$' | get --optional 0.t
    if $tail == null { fail "bootstrap.nu has no CMDLINE_TAIL" }
    let hardening = harden-tokens []
    let install = $tail | split row " " | where { (key-of $in) not-in $INSTALL_ONLY }
    let missing = $install | where $it not-in $hardening
    if ($missing | is-not-empty) { fail $"the install sets ($missing | to nuon), which boot/hardening does not keep" }
    if not (keys-unique $hardening) { fail $"a key twice in the defaults: ($hardening | to nuon)" }

    let cases = [
        [what allow_smt relax want_has want_not];
        ["defaults" true false ["init_on_alloc=1" "init_on_free=1" "iommu.strict=1" slab_nomerge] []]
        ["relaxed" true true ["init_on_alloc=0" "init_on_free=0" "iommu.strict=0" "retbleed=stuff" slab_nomerge]
            ["init_on_alloc=1" "init_on_free=1" "iommu.strict=1"]]
    ]
    for c in $cases {
        let step = with-env {FORM_FACTOR: desktop} { system {allow_smt: $c.allow_smt, relax_mitigations: $c.relax} }
        if $step.target != harden { fail $"($c.what): the verb runs ($step.target), not harden" }
        let tokens = harden-tokens $step.argv
        let lacking = $c.want_has | where $it not-in $tokens
        let kept = $c.want_not | where $it in $tokens
        if ($lacking | is-not-empty) or ($kept | is-not-empty) or not (keys-unique $tokens) {
            fail $"($c.what): ($tokens | to nuon) lacks ($lacking | to nuon), keeps ($kept | to nuon)"
        }
    }
}
