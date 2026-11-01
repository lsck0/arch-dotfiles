# Git clone urls and checkout names from a full url or a github user/repo shorthand.

const GITHUB = "https://github.com"
# an owner has no dots, a repo may start with one (.github) but is no dot segment
const GITHUB_SHORTHAND = '^[A-Za-z0-9][A-Za-z0-9_-]*/(?!\.\.?$)[A-Za-z0-9_.-]+$'

# A url (with a scheme, or scp-like git@) as given, user/repo as its github https url, null for anything else.
export def repository-url [spec: string]: nothing -> oneof<string, nothing> {
    if $spec =~ '://' or ($spec | str starts-with "git@") { return $spec }
    if $spec =~ $GITHUB_SHORTHAND { return $"($GITHUB)/($spec | str replace --regex '\.git$' '').git" }
    null
}

export def repository-name [url: string]: nothing -> string {
    $url | str replace --regex '\.git$' '' | path basename
}
