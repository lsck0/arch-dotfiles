#!/usr/bin/env -S nu --no-config-file
# words-misuse answers what nushell's parser would answer with its own frame: an unknown flag or subcommand, a word
# too many, a missing word or flag value, each as one line naming the command's help; what the signature takes, a
# --help anywhere and an open command pass.
use complete.nu [words-misuse]
use std/assert

def param [name: string, type: string, --optional, --short: string]: nothing -> record {
    {parameter_name: $name, parameter_type: $type, is_optional: $optional, short_flag: $short}
}

const OPEN = [internal]

def main []: nothing -> nothing {
    let table = [
        [name params];
        [status [(param brief switch --optional --short b) (param json switch --optional)]]
        [log [(param run positional --optional) (param level named --optional)]]
        [explain [(param thing positional)]]
        [plan [(param mods rest --optional) (param order switch --optional)]]
        [module []]
        ["module adopt" [(param file positional)]]
        [internal [(param args rest --optional)]]
    ]
    let cases = [
        [words want];
        [[status] null]
        [[status --brief --json] null]
        [[status -b] null]
        [[status --bogus] "dot status has no flag --bogus; dot status --help lists them"]
        [[status -x] "dot status has no flag -x; dot status --help lists them"]
        [[status --bogus --help] "dot status has no flag --bogus; dot status --help lists them"]
        [[status --help --bogus] null]
        [[status extra] "dot status takes no 'extra'; dot status --help says what it takes"]
        [[log] null]
        [[log 20261115T235825-yl6z --level WARN] null]
        [[log --level=WARN] null]
        [[log --level] "dot log: --level needs a value; dot log --help says which"]
        [[log --level WARN --bogus] "dot log has no flag --bogus; dot log --help lists them"]
        [[log a b] "dot log takes no 'b'; dot log --help says what it takes"]
        [[explain] "dot explain needs <thing>; dot explain --help says what it takes"]
        [[explain "-1"] null]
        [[plan a b c --order] null]
        [[module] null]
        [[module foo] "unknown command 'module foo'; dot module --help lists them"]
        [[module adopt] "dot module adopt needs <file>; dot module adopt --help says what it takes"]
        [[module adopt /etc/x] null]
        [[internal gen --anything] null]
        [[aply --force] null]
        [[] null]
    ]
    for c in $cases {
        assert equal (words-misuse $table $c.words $OPEN) $c.want $"dot ($c.words | str join ' ')"
    }
}
