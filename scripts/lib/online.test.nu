#!/usr/bin/env -S nu --no-config-file
# A failed probe says why only when it can tell: a name that did not resolve, resolved running strict DNS-over-TLS and
# its server taking tcp but not on 853. Every other failure, and any machine whose probe went through, stays plain
# offline or online, never a false DNS-over-TLS claim.
use online.nu [resolved-tls-server offline-pending pending-is-network remote-pending OFFLINE_PENDING DNS_TLS_PENDING]
use std/assert

const STRICT = "Global
           Protocols: -LLMNR -mDNS +DNSOverTLS DNSSEC=allow-downgrade/supported
    resolv.conf mode: stub
  Current DNS Server: 9.9.9.9#dns.quad9.net
         DNS Servers: 9.9.9.9#dns.quad9.net 2620:fe::fe#dns.quad9.net
Fallback DNS Servers: 149.112.112.112#dns.quad9.net 2620:fe::9#dns.quad9.net
          DNS Domain: ~.

Link 2 (enp1s0)
    Current Scopes: DNS
         Protocols: +DefaultRoute -LLMNR -mDNS +DNSOverTLS DNSSEC=allow-downgrade/supported
Current DNS Server: 192.168.122.1
"
# portmaster's global drop-in: dot off, its own upstream answers
const PLAIN = "Global
           Protocols: -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
  Current DNS Server: 127.0.0.1
"
const NO_CURRENT = "Global
           Protocols: +DNSOverTLS
         DNS Servers: 2620:fe::fe%enp1s0#dns.quad9.net 9.9.9.9#dns.quad9.net
"
const UNRESOLVED = {exit_code: 6, stderr: "curl: (6) Could not resolve host: github.com\n"}
const RESOLVE_TIMEOUT = {exit_code: 28, stderr: "curl: (28) Resolving timed out after 5002 milliseconds\n"}
const CONNECT_TIMEOUT = {exit_code: 28, stderr: "curl: (28) Connection timed out after 5001 milliseconds\n"}
const REFUSED = {exit_code: 7, stderr: "curl: (7) Failed to connect to github.com port 443\n"}

def server-cases []: nothing -> nothing {
    assert equal (resolved-tls-server $STRICT) "9.9.9.9" "strict: the global current server"
    assert equal (resolved-tls-server $PLAIN) null "dot off globally: no server to blame"
    assert equal (resolved-tls-server $NO_CURRENT) "2620:fe::fe" "no current server: the first listed, bare"
    assert equal (resolved-tls-server "") null "no resolvectl output"
}

def pending-cases []: nothing -> nothing {
    let only_853 = {|address, port| $port != 853 }
    let none = {|address, port| false }
    let all = {|address, port| true }
    let cases = [
        [name probe status reach wants];
        ["853 dropped, 443 through" $UNRESOLVED $STRICT $only_853 $DNS_TLS_PENDING]
        ["the lookup ran out of curl's time" $RESOLVE_TIMEOUT $STRICT $only_853 $DNS_TLS_PENDING]
        ["no tcp at all: plain offline" $UNRESOLVED $STRICT $none $OFFLINE_PENDING]
        ["853 open: something else" $UNRESOLVED $STRICT $all $OFFLINE_PENDING]
        ["names resolved, the connect timed out (the kill switch)" $CONNECT_TIMEOUT $STRICT $only_853 $OFFLINE_PENDING]
        ["refused" $REFUSED $STRICT $only_853 $OFFLINE_PENDING]
        ["dot off" $UNRESOLVED $PLAIN $only_853 $OFFLINE_PENDING]
    ]
    for c in $cases {
        assert equal (offline-pending $c.probe $c.status $c.reach) $c.wants $c.name
    }
    # the connects are the probe's cost offline: none unless the lookup failed under strict dot
    let asked = offline-pending $CONNECT_TIMEOUT $STRICT {|address, port| error make {msg: "connected"} }
    assert equal $asked $OFFLINE_PENDING "a connect asked for a failure that was no lookup"
}

def network-cases []: nothing -> nothing {
    for text in [$OFFLINE_PENDING $DNS_TLS_PENDING (remote-pending "returned error: 503") (remote-pending "Could not resolve host: x")] {
        assert (pending-is-network $text) $"not the network's: ($text)"
    }
    for text in ["packages missing: tor" "waits on core/cli (pending)" "waits on /x, not there yet"] {
        assert not (pending-is-network $text) $"the network's: ($text)"
    }
}

def main [] {
    server-cases
    pending-cases
    network-cases
}
