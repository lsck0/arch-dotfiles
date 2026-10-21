#!/usr/bin/env -S nu --no-config-file
use lib.nu [notify cycle-next]

const GRADING = path self ../../configs/desktop/color-grading/color-grading.py

def grading []: nothing -> record { ^$GRADING status | from json }

def preset-label [preset: string]: nothing -> string { grading | get presets | where name == $preset | get label.0 }

def apply [preset: string]: nothing -> nothing {
    ^$GRADING set preset $preset
    notify "Color grading" (preset-label $preset)
}

def "main get" [] { grading | get preset }
def "main list" [] { print (grading | get presets.name | str join "\n") }

def "main label" [] {
    match (grading | get preset) {
        off => "○ Color grading: Off"
        $preset => $"● Color grading: (preset-label $preset)"
    }
}

def "main on" [] { apply default }
def "main off" [] { apply off }
def "main set" [preset: string] { apply $preset }
def "main toggle" [] { let status = grading; apply ($status.presets.name | cycle-next $status.preset) }
def main [] { main toggle }
