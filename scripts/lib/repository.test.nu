#!/usr/bin/env -S nu --no-config-file
# Table cases for repository-url and repository-name: urls kept, user/repo to github, anything else refused. And
# repository-find-under on a real tree: checkouts, bare repos and linked worktrees, never a submodule, a pruned dir or
# what lies past the depth.
use repository.nu [repository-url repository-name repository-find-under]
use state.nu [tmp-dir-run]
use std/assert

def --wrapped git-quiet [...args: string]: nothing -> nothing {
    ^git -c init.defaultBranch=main -c user.name=t -c user.email=t@t -c protocol.file.allow=always ...$args out+err> /dev/null
}

def find-cases [work: path]: nothing -> nothing {
    git-quiet init ($work | path join a)
    git-quiet -C ($work | path join a) commit --allow-empty -m x
    git-quiet -C ($work | path join a) worktree add ($work | path join wt)
    git-quiet init --bare ($work | path join group b.git)
    git-quiet -C ($work | path join a) push ($work | path join group b.git) main
    git-quiet init ($work | path join node_modules c)
    git-quiet init ($work | path join x y z deep)
    git-quiet -C ($work | path join a) submodule add ($work | path join group b.git) sub
    let got = repository-find-under $work 2 | update dir { path relative-to $work }
    let wants = [[dir kind]; [a checkout] [group/b.git bare] [wt worktree]]
    assert equal $got $wants $"found ($got | to nuon)"
}

def main [] {
    tmp-dir-run {|work| find-cases $work }
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
