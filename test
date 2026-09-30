#!/usr/bin/env bash
# end-to-end: fresh arch vm, bootstrap.sh from the iso, the install/config chain on the local working tree (or github master with --master); exits 1 on any failure
exec "$(dirname "$(readlink -f "$0")")/vm-test/vm-test.py" run "$@"
