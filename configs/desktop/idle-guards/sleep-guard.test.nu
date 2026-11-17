#!/usr/bin/env -S nu --no-config-file
# the mic guard's predicate: a running microphone holds, a monitor or an idle microphone does not
use sleep-guard.nu [mic-recording]

def fail [msg: string] { error make {msg: $"sleep-guard.test: ($msg)"} }

def node [class: string, state: string]: nothing -> record {
    {state: $state, properties: {"media.class": $class}}
}

def main [] {
    let cases = [
        [name sources want];
        [none [] false]
        [mic-suspended [(node Audio/Source SUSPENDED)] false]
        [mic-idle [(node Audio/Source IDLE)] false]
        [mic-running [(node Audio/Source RUNNING)] true]
        [virtual-running [(node Audio/Source/Virtual RUNNING)] true]
        [monitor-running [(node Audio/Sink RUNNING)] false]
        [no-class [{state: RUNNING}] false]
        [one-of-two [(node Audio/Source SUSPENDED) (node Audio/Source RUNNING)] true]
    ]
    for c in $cases {
        let got = $c.sources | mic-recording
        if $got != $c.want { fail $"($c.name): ($got)" }
    }
}
