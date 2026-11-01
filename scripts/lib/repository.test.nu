#!/usr/bin/env -S nu --no-config-file
# Table cases for repository-url and repository-name: urls kept, user/repo to github, anything else refused.
use repository.nu [repository-url repository-name]
use std/assert

def main [] {
    let cases = [
        [spec url name];
        ["user/repo" "https://github.com/user/repo.git" "repo"]
        ["user/repo.git" "https://github.com/user/repo.git" "repo"]
        ["https://example.org/a/b.git" "https://example.org/a/b.git" "b"]
        ["ssh://git@example.org:2222/a/b" "ssh://git@example.org:2222/a/b" "b"]
        ["git@github.com:user/repo.git" "git@github.com:user/repo.git" "repo"]
        ["repo" null null]
        ["/abs/path" null null]
        ["a/b/c" null null]
        ["./x" null null]
        ["../x" null null]
        ["a/.." null null]
        ["user/.github" "https://github.com/user/.github.git" ".github"]
        ["" null null]
    ]
    for c in $cases {
        let url = repository-url $c.spec
        assert equal $url $c.url $"($c.spec): url ($url | to nuon), wants ($c.url | to nuon)"
        let name = if $url == null { null } else { repository-name $url }
        assert equal $name $c.name $"($c.spec): name ($name | to nuon), wants ($c.name | to nuon)"
    }
}
