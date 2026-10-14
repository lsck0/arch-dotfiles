#!/usr/bin/env -S nu --no-config-file
# launcher ids to hide beyond NoDisplay: Hidden=true, or OnlyShowIn/NotShowIn against the desktops in $1 (a:b)

const DATA_DIRS_DEFAULT = "/usr/local/share:/usr/share"
const SECTION = "[Desktop Entry]"

def entry-hidden [file: string, desktops: list<string>]: nothing -> bool {
    let keys = open --raw $file
        | lines
        | str trim -r -c "\r"
        | skip until { $in == $SECTION }
        | skip 1
        | take until { $in =~ '^\[.*\]$' }
        | parse "{key}={value}"
    let value = {|key| $keys | where key == $key | get value | last 1 | get 0? | default "" }
    let listed = {|key| do $value $key | split row ";" | any { $in != "" and $in in $desktops } }
    let only_shown = do $value OnlyShowIn
    let not_shown = do $value NotShowIn
    (
        ($keys | any { $in.key == Hidden and $in.value == "true" })
        or ($only_shown != "" and not (do $listed OnlyShowIn))
        or ($not_shown != "" and (do $listed NotShowIn))
    )
}

def main [desktops: string = ""] {
    let wanted = $desktops | split row ":"
    $env.XDG_DATA_DIRS? | default $DATA_DIRS_DEFAULT | split row ":"
        | prepend ($env.HOME | path join .local/share)
        | append ($env.HOME | path join .nix-profile/share)
        | each { path join applications }
        | where { ($in | path expand | path type) == dir }
        | each {|dir|
            glob --follow-symlinks $"($dir)/**/*.desktop" | sort | each {|file|
                {id: ($file | path relative-to $dir | str replace -r '\.desktop$' '' | str replace -a / -), file: $file}
            }
        }
        | flatten
        | uniq-by id
        | par-each -k {|e| if (entry-hidden $e.file $wanted) { $e.id } }
        | each { print } | ignore
}
