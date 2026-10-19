#!/usr/bin/env -S nu --no-config-file
# lib/citation.lua: bib parsing, project-over-zotero precedence, cite insertion in tex and markdown
const CONFIG = path self .

def main [] {
    let dir = mktemp --directory
    let run = ^nvim --clean -l ($CONFIG | path join citation.test.lua) $CONFIG $dir | complete
    rm --recursive $dir
    if $run.exit_code != 0 {
        print -e ($run.stdout + $run.stderr | str trim)
        exit 1
    }
    print "citation.test: ok"
}
