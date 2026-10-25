#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run]
use ../../configs/base/tor/anonymous-socks.nu *

def main [action: string = "toggle", --json] {
    switch-run {
        label: "Anonymous SOCKS"
        is-on: {|| (anonymous-socks-status) == on }
        on: {|| anonymous-socks-up }
        off: {|| anonymous-socks-down }
    } $action --json=$json
}

# every pool port reachable and leaving through a tor exit
def "main check" [] { anonymous-socks-check }

# fresh circuits for new streams
def "main newnym" [] { anonymous-socks-newnym }

# the [ProxyList] block of the live pool
def "main proxylist" [] { anonymous-socks-proxylist | print -n }

# the whole proxychains config of the live pool
def "main proxyconf" [] { anonymous-socks-proxyconf | print -n }
