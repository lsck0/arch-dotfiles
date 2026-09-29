#!/usr/bin/env bash
# passphrase from the login keyring
exec secret-tool lookup ssh-key ssh_privatekey
