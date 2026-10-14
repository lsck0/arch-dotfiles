#!/usr/bin/env -S nu --no-config-file

const REPO = path self | path expand | path dirname --num-levels 2
const SCAFFOLD = $REPO | path join skills l-agent-task-db scripts scaffold.nu

# Scaffold an agent task db in a project dir (default: the current dir).
def main [project_dir?: path]: nothing -> nothing {
    exec $SCAFFOLD ($project_dir | default $env.PWD)
}
