# base/pam maps the owner's yubikey to the logins listed in /var/lib/dotfiles/owners instead of the name "luca" in
# u2f_keys: seed the list once from the logins installed with an identity profile, so sudo keeps its touch
export const layer = "system"

const OWNERS = "/var/lib/dotfiles/owners"

export def up []: nothing -> nothing {
    let found = open --raw /etc/passwd | lines | parse "{name}:{x}:{uid}:{gid}:{gecos}:{home}:{shell}"
        | where ($it.uid | into int) >= 1000 and ($it.uid | into int) < 60000
        | where {|u|
            let profile = $u.home | path join .config dotfiles profile.nuon
            ($profile | path exists) and ("identity" in (try { open $profile | get --optional capabilities | default [] } catch { [] }))
        } | get name
    let have = if ($OWNERS | path exists) { open --raw $OWNERS | lines } else { [] }
    let all = $have | append $found | uniq | where $it != ""
    if ($all | is-empty) { return }
    mkdir ($OWNERS | path dirname)
    $all | str join "\n" | $"($in)\n" | save --force $OWNERS
}

export def down []: nothing -> nothing {}
