#!/usr/bin/env -S nu --no-config-file
# docker.socket stays enabled either way: the first `docker` command lazy-starts it
use lib.nu [switch-run service-switch]

def main [action: string = "toggle"] { switch-run (service-switch Docker docker.service) $action }
