#!/usr/bin/env bash
# ssh-add askpass: hand over the key passphrase stored in the login keyring
exec secret-tool lookup ssh-key ssh_privatekey
