#!/usr/bin/env -S nu --no-config-file
# toggle-root runs as root on arguments any process of the session chooses. nu evaluates a --flag=(expr) argument of
# a script before main wherever the signature takes it (--wrapped, or a flag with a value), so the helper itself is
# run here, unprivileged, on such arguments: each must be refused with nothing evaluated. 49-toggles.rules is the
# second layer: its verb lists must take the helper's verbs and nothing with a flag or an expression in it.

use toggle-root.nu [anonsocks-rate-cap-loaded]
use ../../../scripts/launchers.test.nu [hostile]

const HERE = path self .
const HELPER = $HERE | path join toggle-root.nu
const RULES = $HERE | path join 49-toggles.rules
const PERSONA_CGROUP = "user.slice/user-1000.slice/user@1000.service/app.slice/anonymous-socks-tor.service"

def fail [msg: string] { error make {msg: $"toggle-root.test: ($msg)"} }

# Every argv ends in usage or a parse error, so none reaches a verb's commands.
def injections [marker: path]: nothing -> list<list<string>> {
    hostile $marker | where { $in | str contains $marker } | each {|form| [[$form] [tlp $form] [$form tlp balanced] [anonsocks persona-on "64" $form] [guard-stop $form]] }
    | flatten
}

def helper-refuses []: nothing -> nothing {
    let work = mktemp --directory
    let marker = $work | path join evaluated
    for argv in (injections $marker) {
        let run = ^$HELPER ...$argv | complete
        let evaluated = $marker | path exists
        rm --force $marker
        if $evaluated { rm --recursive $work; fail $"evaluated an argument: ($argv | to nuon)" }
        if $run.exit_code == 0 { rm --recursive $work; fail $"accepted ($argv | to nuon)" }
    }
    rm --recursive $work
    if (open --raw $HELPER) !~ '(?m)^def main \[\.\.\.args: string\] \{$' {
        fail "main must stay `def main [...args: string]`: --wrapped or a flag makes nu evaluate arguments as root"
    }
}

# A verb list of the rules file as one anchored pattern, built the way the rule builds it.
def rule-verbs [name: string]: nothing -> string {
    let list = '(?s)var ' + $name + ' = new RegExp\("\^\(" \+ \[(?<list>.*?)\]\.join'
    let block = open --raw $RULES | parse --regex $list | get 0.list
    let verbs = $block | parse --regex '"(?<verb>[^"\n]+)"' | get verb | str replace --all '\\' '\'
    $"^\(($verbs | str join '|')\)$"
}

def rule-allowlist []: nothing -> nothing {
    let unprompted = rule-verbs VERBS_UNPROMPTED
    let lowering = rule-verbs VERBS_LOWERING
    let cases = [
        [verb unprompted lowering];
        ["tlp balanced" true false] ["tlp start" true false] ["wg down" true false] ["vllm on" true false]
        ["firewall restrictive" true false] ["firewall raise-default" true false] ["portal off" true false]
        ["portmaster-restore" true false] ["tor-start" true false]
        ["anonsocks nft-off" true false] ["anonsocks rate-on 9061 10 5" true false]
        [$"anonsocks persona-on 128 ($PERSONA_CGROUP)" true false]
        ["firewall default" false true] ["firewall permissive" false true] ["portal on" false true]
        ["guard-stop portmaster.service" false true] ["guard-stop tor-router.service portmaster.service" false true]
        ["" false false] ["tlp" false false] ["tlp balanced " false false] ["tlp --x=(id)" false false]
        ["tlp balanced --x=(id)" false false] ["--x=(id) tlp balanced" false false] ["firewall" false false]
        ["guard-stop" false false] ["guard-stop fw-lockdown.service" false false] ["wg up\n" false false] ["tor-start tor-router.service" false false]
        ["anonsocks rate-on 1 1 1 --x=(id)" false false] ["anonsocks persona-on 64 user.slice/(id)" false false]
        ["anonsocks persona-on 64 /etc" false false] ["portal on --x=$(id)" false false]
    ]
    for c in $cases {
        let got = {unprompted: ($c.verb =~ $unprompted), lowering: ($c.verb =~ $lowering)}
        if $got != ($c | reject verb) { fail $"rule on '($c.verb)': ($got | to nuon)" }
    }
    if (open --raw $RULES | str trim) !~ '(?s)return polkit\.Result\.NO;\n\}\);$' {
        fail "the helper's rule must end by refusing every other command line"
    }
}

# nft's own listing of the rule the helper loads, for a pool and for one port.
def rate-cap-listing [dport: string, rate: int, extra: string = ""]: nothing -> string {
    $"table inet anonymous_socks {
\tchain out {
\t\ttype filter hook output priority filter; policy accept;
\t\toif \"lo\" tcp dport ($dport) ct state new limit rate over ($rate)/second burst 5 packets drop
($extra)\t}
}
"
}

def rate-cap-compare []: nothing -> nothing {
    let pool = rate-cap-listing "9061-9070" 5
    let cases = [
        [listing port last rate want];
        [$pool 9061 9070 5 true] [(rate-cap-listing "9061" 5) 9061 9061 5 true]
        [$pool 9061 9070 50 false] [$pool 9061 9071 5 false] [$pool 9060 9070 5 false] [$pool 9061 9061 5 false]
        [(rate-cap-listing "9061-9070" 5 "\t\taccept\n") 9061 9070 5 false]
        [(rate-cap-listing "1-65535" 5) 9061 9070 5 false] ["" 9061 9070 5 false]
    ]
    for c in $cases {
        let got = anonsocks-rate-cap-loaded $c.listing $c.port $c.last $c.rate
        if $got != $c.want { fail $"rate cap ($c.port)-($c.last) at ($c.rate) against ($c.listing | to nuon): ($got)" }
    }
}

def main [] {
    helper-refuses
    rule-allowlist
    rate-cap-compare
}
