#!/usr/bin/env -S nu --no-config-file
# lib/python.lua resolves $VIRTUAL_ENV, then root/.venv, then the poetry env, else nothing; checked in headless nvim on
# scratch projects, with a stub poetry on PATH for the poetry branch.

use std/assert

const HERE = path self .

def python-stub [dir: string] {
    mkdir ($dir | path join bin)
    let python = $dir | path join bin python
    "#!/bin/sh\n" | save $python
    ^chmod +x $python
    $python
}

def python-find [root: any, env_extra: record = {}] {
    let script = $"package.path = ($HERE | path join config lua ?.lua | to json) .. ';' .. package.path
local root = vim.json.decode\(($root | to json | to json)\)
io.stdout:write\(vim.json.encode\({ python = require\('lib.python'\).find\(root\) or vim.NIL }\)\)"
    let file = mktemp --tmpdir dot-python-test-XXXXXX.lua
    $script | save --force $file
    hide-env --ignore-errors VIRTUAL_ENV
    let run = with-env $env_extra { ^nvim --clean --headless -l $file | complete }
    rm --force $file
    assert equal $run.exit_code 0 $"nvim: ($run.stderr | str trim)"
    $run.stdout | from json | get python
}

def main [] {
    if (which nvim | is-empty) { print "python.test: skipped, needs nvim"; return }
    let work = mktemp --directory --tmpdir dot-python-test-XXXXXX
    # nvim --clean still opens its log under the state dir: the test's own, never the user's nvim.log
    $env.XDG_STATE_HOME = $work | path join state
    let bare = $work | path join bare
    mkdir $bare
    let project = $work | path join project
    let dotvenv = python-stub ($project | path join .venv)
    "" | save ($project | path join pyproject.toml)
    let active = python-stub ($work | path join active)
    let poetry_project = $work | path join poetry
    mkdir $poetry_project
    "" | save ($poetry_project | path join pyproject.toml)
    let poetry_env = $work | path join poetry-env bin python
    mkdir ($work | path join stub)
    let poetry = $work | path join stub poetry
    $"#!/bin/sh\n[ \"$POETRY_STUB_FAIL\" = 1 ] && exit 1\necho ($poetry_env)\n" | save $poetry
    ^chmod +x $poetry
    let base = {}
    let stubbed = {PATH: ($env.PATH | prepend ($work | path join stub))}

    assert equal (python-find null $base) null "null root"
    assert equal (python-find "" $base) null "empty root"
    assert equal (python-find $bare $base) null "neither"
    assert equal (python-find $project $base) $dotvenv ".venv"
    assert equal (python-find $project {VIRTUAL_ENV: ($work | path join active)}) $active "VIRTUAL_ENV over .venv"
    assert equal (python-find $project {VIRTUAL_ENV: $bare}) $dotvenv "VIRTUAL_ENV without python"
    assert equal (python-find $poetry_project $stubbed) $poetry_env "poetry env"
    assert equal (python-find $poetry_project ($stubbed | merge {POETRY_STUB_FAIL: "1"})) null "poetry failing"
    assert equal (python-find $project $stubbed) $dotvenv ".venv over poetry"
    rm --recursive --force $work
}
