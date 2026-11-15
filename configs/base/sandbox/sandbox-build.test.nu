#!/usr/bin/env -S nu --no-config-file
# What sandbox-build hides from a build is also denied to the AppArmor file-tool profiles, and every home path those
# deny outright is hidden from a build: the two lists cannot drift apart.

const HERE = path self .
const SENSITIVE_HOME_FILE = $HERE | path join sensitive-home.txt
const ABSTRACTIONS = $HERE | path join .. apparmor abstractions
const FILE_TOOL_RULES = [deny-sensitive-home file-tool]
const DENY_ALL = "mrwkl,"
# apparmor.d's tunables as home-relative paths
const TUNABLES = {
    "@{HOME}/": ""
    "@{user_config_dirs}": ".config"
    "@{user_share_dirs}": ".local/share"
    "@{user_state_dirs}": ".local/state"
    "@{user_ssh_dirs}": ".ssh"
    "@{user_gpg_dirs}": ".gnupg"
    "@{user_passwordstore_dirs}": ".password-store"
    "@{user_sync_dirs}": "sync"
}
# a file tool works on these: archives and media in ~/sync, an agent's transcripts, dot's own state
const FILE_TOOL_READS = [sync .claude .config/dotfiles]
# denied by a glob, which str expand does not resolve
const GLOB_DENIED = {".aws": ".*aws*"}

# Home-relative paths the file-tool profiles are denied all access to, braces expanded.
def denied-paths []: nothing -> list<string> {
    $FILE_TOOL_RULES | each {|name| open --raw ($ABSTRACTIONS | path join $name) | lines } | flatten
    | str trim | where { ($in | str starts-with "deny ") and ($in | str ends-with $DENY_ALL) }
    | each {|rule|
        let pattern = $rule | split row --regex '\s+' | get 1
        $TUNABLES | transpose k v | reduce --fold $pattern {|t, acc| $acc | str replace $t.k $t.v }
    }
    | where { not ($in | str starts-with "@{") }
    | each { if ($in | str contains "{") { $in | str expand } else { [$in] } } | flatten
}

def main []: nothing -> nothing {
    let denied = denied-paths
    let hidden = open --raw $SENSITIVE_HOME_FILE | lines
    let readable = $hidden | where $it not-in $FILE_TOOL_READS | where {|p|
        let forms = [$p $"($p)/" $"($p)/**" ($GLOB_DENIED | get --optional $p | default $p)]
        $forms | all { $in not-in $denied }
    } | each { $"($in) is hidden from sandbox-build but readable by the file-tool profiles" }
    let whole = $denied | where { $in | str ends-with "/**" } | str replace --regex '/\*\*$' ""
        | where { $in !~ '[*?\[]' }
    let visible = $whole | where {|d| not ($hidden | any {|p| $d == $p or ($d | str starts-with $"($p)/") }) }
        | each { $"($in) is denied to the file-tool profiles but visible to sandbox-build" }
    let failures = $readable ++ $visible
    for f in $failures { print --stderr $"sandbox-build.test: ($f)" }
    if ($failures | is-not-empty) { exit 1 }
}
