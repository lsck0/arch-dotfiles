#!/usr/bin/env -S nu --no-config-file
# The link verb evaluates with the network denied (a fresh net namespace) and no lazy.nvim installed, as on a fresh
# install off the network: its probes never bootstrap lazy, so it returns within seconds and asks for the prefetch step.

const HERE = path self | path dirname
const LIB = path self ../../../scripts/lib
const EVAL_WAIT_MAX = 20sec

def fail [msg: string] { error make {msg: $"nvim.test: ($msg)"} }

def main [] {
    if (which nvim unshare | length) < 2 { print "nvim.test: skipped, needs nvim and unshare"; return }
    if (do { ^unshare --net --map-current-user true } | complete).exit_code != 0 { print "nvim.test: skipped, no user namespaces"; return }
    let work = mktemp --directory --tmpdir dot-nvim-test-XXXXXX
    let dirs = {XDG_CONFIG_HOME: config, XDG_DATA_HOME: data, XDG_STATE_HOME: state, XDG_CACHE_HOME: cache} | items {|k, d|
        mkdir ($work | path join $d)
        {$k: ($work | path join $d)}
    } | into record
    ^ln -s $HERE ($work | path join config nvim)
    let call = $"cd ($HERE | to nuon); use ($HERE | to nuon); nvim link {} | where kind == step | to nuon"
    let start = date now
    let run = with-env ($dirs | merge {HOME: $work}) {
        ^timeout ($EVAL_WAIT_MAX / 1sec) unshare --net --map-current-user nu --no-config-file -I $LIB -c $call | complete
    }
    let took = (date now) - $start
    rm --recursive --force $work
    if $run.exit_code != 0 { fail $"link exited ($run.exit_code) after ($took): ($run.stderr | str trim)" }
    if $took > $EVAL_WAIT_MAX { fail $"link took ($took), wants within ($EVAL_WAIT_MAX)" }
    let steps = $run.stdout | from nuon
    let prefetch = $steps | where target == prefetch | get --optional 0
    if $prefetch == null { fail $"no prefetch step declared: ($steps | to nuon)" }
    if not $prefetch.network { fail "the prefetch step does not declare --network" }
}
