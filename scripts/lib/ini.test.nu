#!/usr/bin/env -S nu --no-config-file
# ini-apply sets, adds and seeds keys per section; a mod.nu exporting an update verb that imports ini.nu still runs it.
use ini.nu [ini-apply]
use std/assert

const LIB = path self .

def apply-cases []: nothing -> nothing {
    let cases = [
        [name text values missing_only wants];
        ["a key set in place" "[a]\nk=1\n" {a: {k: 2}} false "[a]\nk=2\n"]
        ["a key added to its section" "[a]\nk=1\n[b]\n" {a: {j: x}} false "[a]\nk=1\nj=x\n[b]\n"]
        ["a section added" "[a]\nk=1\n" {b: {k: 1}} false "[a]\nk=1\n\n[b]\nk=1\n"]
        ["before the first header" "k=1\n[a]\n" {"": {k: 2}} false "k=2\n[a]\n"]
        ["missing only keeps a set key" "[a]\nk=1\n" {a: {k: 2, j: 3}} true "[a]\nk=1\nj=3\n"]
        ["an empty text" "" {a: {k: 1}} false "[a]\nk=1\n"]
    ]
    for c in $cases { assert equal ($c.text | ini-apply $c.values $c.missing_only) $c.wants $c.name }
}

# nu declares a file's defs before it parses that file's imports, so a module's update verb shadows the builtin there
def shadow-cases [work: path]: nothing -> nothing {
    let dir = $work | path join module
    mkdir $dir
    $"use ($LIB | path join ini.nu) [ini-apply]\nexport def update [cfg: record] { }\nexport def link [cfg: record] { \"[a]\\nk=1\\n\" | ini-apply {a: {k: 2}} false }\n"
    | save ($dir | path join mod.nu)
    let run = ^$nu.current-exe --no-config-file -c $"use ($dir | path join mod.nu) [link]; link {} | to nuon" | complete
    assert equal $run.exit_code 0 $"ini-apply under a module with an update verb: ($run.stderr)"
    assert equal ($run.stdout | str trim) ("[a]\nk=2\n" | to nuon) "ini-apply under a module with an update verb"
}

def main [] {
    apply-cases
    let work = mktemp --directory
    try { shadow-cases $work } catch {|e| rm --recursive --force $work; error make $e }
    rm --recursive --force $work
}
