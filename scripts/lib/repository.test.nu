#!/usr/bin/env -S nu --no-config-file
# Table cases for repository-url and repository-name: urls kept, user/repo to github, anything else refused.
use repository.nu [repository-url repository-name]

def fail [msg: string] { error make {msg: $"repository.test: ($msg)"} }

def main [] {
    let cases = [
        [spec url name];
        ["user/repo" "https://github.com/user/repo.git" "repo"]
        ["user/repo.git" "https://github.com/user/repo.git" "repo"]
        ["https://example.org/a/b.git" "https://example.org/a/b.git" "b"]
        ["ssh://git@example.org:2222/a/b" "ssh://git@example.org:2222/a/b" "b"]
        ["git@github.com:user/repo.git" "git@github.com:user/repo.git" "repo"]
        ["repo" null null]
        ["" null null]
    ]
    for c in $cases {
        let url = repository-url $c.spec
        if $url != $c.url { fail $"($c.spec): url ($url | to nuon), wants ($c.url | to nuon)" }
        let name = if $url == null { null } else { repository-name $url }
        if $name != $c.name { fail $"($c.spec): name ($name | to nuon), wants ($c.name | to nuon)" }
    }
}
