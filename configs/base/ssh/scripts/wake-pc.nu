#!/usr/bin/env -S nu --no-config-file -I @DOTFILES@/configs/base/ssh/scripts
# Wakes the desktop through the homelab router, asks its initramfs for the disk passphrase when it stops there, then
# ssh-es in through the knock.
use wake.nu [host-wake]

const ROUTER = "@ROUTER@"
const ROUTER_TUNNEL = "@ROUTER_TUNNEL@"
const PC = "@HOST@"
const KNOCK = [@KNOCK@]
const PORT = "@PORT@"
# base/boot/remote-unlock's tinysshd (tinysshd.conf): the initramfs asks there for the LUKS passphrase
const UNLOCK_PORT = "@UNLOCK_PORT@"

def main []: nothing -> nothing {
    let config = {
        host: $PC, port: ($PORT | into int), knock: $KNOCK, router: $ROUTER
        router_tunnel: (if $ROUTER_TUNNEL == "" { null } else { $ROUTER_TUNNEL }), unlock_port: ($UNLOCK_PORT | into int)
    }
    host-wake $config --unlock-interactive
    exec sshk $PC
}
