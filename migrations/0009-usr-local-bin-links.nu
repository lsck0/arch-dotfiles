# /usr/local/bin held per-user links into a checkout before the root-owned copy; they go.

export const layer = "system"

export def up []: nothing -> nothing {
    ls /usr/local/bin | where type == symlink | where { (^readlink $in.name | str starts-with "/home/") } | each { rm $in.name } | ignore
}
