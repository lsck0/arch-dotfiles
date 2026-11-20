#!/usr/bin/env -S nu --no-config-file

const REPO = path self | path expand | path dirname --num-levels 2
const SCAFFOLD = $REPO | path join configs secrets skills l-agent-task-db scripts scaffold.nu

# Scaffold an agent task db in a project dir (default: the current dir).
def main [project_dir?: path]: nothing -> nothing {
    # the scaffold lives in the owner's secrets submodule: absent without it, a git-crypt blob while locked
    if not ($SCAFFOLD | path exists) or (open --raw $SCAFFOLD | first 9) == (0x[00] ++ ("GITCRYPT" | into binary)) {
        error make --unspanned {msg: $"taskwarrior-init: needs the unlocked secrets submodule \(($SCAFFOLD)\)"}
    }
    exec $SCAFFOLD ($project_dir | default $env.PWD)
}
