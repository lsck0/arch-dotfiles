#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run service-switch]

def main [action: string = "toggle", --json] { switch-run (service-switch Ollama ollama.service) $action --json=$json }
