#!/usr/bin/env -S nu --no-config-file
# Scaffolds a per-project taskwarrior + timewarrior db and tasks/context/. Safe to re-run.

const HOOK_SRC = "/usr/share/doc/timew/ext/on-modify.timewarrior"
const MARKER_BEGIN = "    # >>> l-agent-task-db taskwarrior env (managed block) >>>"
const MARKER_END = "    # <<< l-agent-task-db taskwarrior env (managed block) <<<"
const ENTER_SHELL = "enterShell = ''"
# plain nix '' string: no ${...} and no doubled single quotes in here
const ENTER_BLOCK = r#'    # >>> l-agent-task-db taskwarrior env (managed block) >>>
    mkdir -p "$DEVENV_ROOT/tasks/.task/hooks" "$DEVENV_ROOT/tasks/.timewarrior"
    printf 'data.location=%s\nhooks.location=%s\n' \
      "$DEVENV_ROOT/tasks/.task" "$DEVENV_ROOT/tasks/.task/hooks" > "$DEVENV_ROOT/tasks/.taskrc"
    if [ ! -e "$DEVENV_ROOT/tasks/.task/hooks/on-modify.timewarrior" ] \
      && [ -f /usr/share/doc/timew/ext/on-modify.timewarrior ]; then
      install -m 755 /usr/share/doc/timew/ext/on-modify.timewarrior "$DEVENV_ROOT/tasks/.task/hooks/"
    fi
    export TASKRC="$DEVENV_ROOT/tasks/.taskrc"
    export TIMEWARRIORDB="$DEVENV_ROOT/tasks/.timewarrior"
    # <<< l-agent-task-db taskwarrior env (managed block) <<<'#
const IGNORED = [tasks/.taskrc tasks/.task/ tasks/.timewarrior/ tasks/.poll-backoff]
const CONTEXT_DIRS = [research design questions]

def in-repo [target: path]: nothing -> bool {
    (^git -C $target rev-parse --is-inside-work-tree | complete).exit_code == 0
}

def devenv-patch [file: path]: nothing -> nothing {
    if not ($file | path exists) {
        $"{ pkgs, lib, config, inputs, ... }:\n\n{\n  ($ENTER_SHELL)\n($ENTER_BLOCK)\n  '';\n}\n" | save $file
        print $"wrote ($file)"
        return
    }
    let text = open --raw $file
    let start = $text | str index-of $MARKER_BEGIN
    let end = if $start == -1 { -1 } else { $text | str index-of $MARKER_END --range $start.. }
    if $end != -1 {
        let stop = $end + ($MARKER_END | str length)
        let fresh = ($text | str substring ..<$start) + $ENTER_BLOCK + ($text | str substring $stop..)
        if $fresh != $text { $fresh | save --force $file }
        print $"refreshed the managed block in ($file)"
    } else if ($text | str contains $ENTER_SHELL) {
        let at = ($text | str index-of $ENTER_SHELL) + ($ENTER_SHELL | str length)
        ($text | str substring ..<$at) + "\n" + $ENTER_BLOCK + ($text | str substring $at..) | save --force $file
        print $"patched existing ($file) \(inserted into its enterShell block\)"
    } else {
        let at = $text | str index-of "}" --end
        if $at == -1 { error make {msg: $"no closing '}' found in ($file); patch it by hand"} }
        let snippet = $"\n  ($ENTER_SHELL)\n($ENTER_BLOCK)\n  '';\n"
        ($text | str substring ..<$at) + $snippet + ($text | str substring $at..) | save --force $file
        print $"patched existing ($file) \(added a new enterShell block\)"
    }
}

def main [target: path = "."]: nothing -> nothing {
    let target = $target | path expand
    let tasks = $target | path join tasks
    let context = $tasks | path join context
    let taskrc = $tasks | path join .taskrc
    let task_data = $tasks | path join .task
    let timew_data = $tasks | path join .timewarrior
    let hook = $task_data | path join hooks on-modify.timewarrior
    let devenv = $target | path join devenv.nix
    let envrc = $target | path join .envrc

    if ($task_data | path exists) { print $"note: ($task_data) already exists; reusing it." }
    # a fresh repo gets one commit of exactly what this script wrote, never `git add -A`
    let repo_new = not (in-repo $target)
    if $repo_new {
        ^git init -q $target
        print $"initialized a new git repo at ($target)"
    } else {
        print $"note: ($target) is already inside a git repo; not running 'git init'."
    }

    mkdir ($task_data | path join hooks) $timew_data
    for dir in $CONTEXT_DIRS {
        mkdir ($context | path join $dir)
        # git drops empty dirs; keep the context/ subfolders visible
        touch ($context | path join $dir .gitkeep)
    }
    # local and gitignored: devenv's enterShell rewrites it from $DEVENV_ROOT on every entry
    $"data.location=($task_data)\nhooks.location=($task_data | path join hooks)\n" | save --force $taskrc
    if not ($hook | path exists) {
        if ($HOOK_SRC | path exists) {
            ^install -m 755 $HOOK_SRC $hook
        } else {
            print -e $"note: ($HOOK_SRC) not found; skipping the timewarrior hook \(install the 'timew' package\)."
        }
    }
    devenv-patch $devenv

    # first line: identity-init appends to .envrc and must stay last
    let rest = if ($envrc | path exists) { open --raw $envrc | lines } else { [] }
    if "use devenv" not-in $rest { ["use devenv"] ++ $rest | str join "\n" | $"($in)\n" | save --force $envrc }

    if (in-repo $target) {
        let gitignore = $target | path join .gitignore
        touch $gitignore
        let have = open --raw $gitignore | lines
        let missing = $IGNORED | where $it not-in $have
        if ($missing | is-not-empty) { $missing | str join "\n" | $"($in)\n" | save --append $gitignore }
        if (^git -C $target ls-files --error-unmatch tasks/.taskrc | complete).exit_code == 0 {
            print -e "note: tasks/.taskrc is tracked but now generated; untrack it: git rm --cached tasks/.taskrc"
        }
    }

    # only for a repo this script just created, committed as the user's own git identity
    if $repo_new {
        ^git -C $target add devenv.nix .envrc .gitignore tasks
        let identity = [user.email user.name] | all {|k| (^git -C $target config $k | complete).exit_code == 0 }
        let staged = (^git -C $target diff --cached --quiet | complete).exit_code != 0
        if $staged and $identity {
            ^git -C $target commit -q -m "Scaffold tasks/ taskwarrior db (l-agent-task-db)"
            print "committed initial scaffold to the new git repo"
        } else if $staged {
            print -e "note: no git user.name/user.email configured; scaffold staged but not committed."
        }
    }

    print $"wrote ($taskrc), ($task_data)/, ($timew_data)/, ($context)/"
    print $"use directly with: TASKRC=\"($taskrc)\" TIMEWARRIORDB=\"($timew_data)\" task ..."
    let direnv = "(requires direnv hooked into your shell rc)."
    print $"or 'direnv allow' in ($target) to auto-export both on every cd ($direnv)"
}
