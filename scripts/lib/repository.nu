# Git clone urls and checkout names from a full url or a github user/repo shorthand.

const GITHUB = "https://github.com"

# A url (with a scheme, or scp-like git@) as given, user/repo as its github https url, null for anything else.
export def repository-url [spec: string]: nothing -> oneof<string, nothing> {
    if $spec =~ '://' or ($spec | str starts-with "git@") { return $spec }
    if $spec =~ '/' { return $"($GITHUB)/($spec | str replace --regex '\.git$' '').git" }
    null
}

export def repository-name [url: string]: nothing -> string {
    $url | str replace --regex '\.git$' '' | path basename
}
