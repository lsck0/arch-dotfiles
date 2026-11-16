#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run service-switch]

# Ollama: get [--json] prints the state, on, off or toggle switches it, a bare call toggles.
def main [action: string = "toggle", --json] { switch-run (service-switch Ollama ollama.service) $action --json=$json }
